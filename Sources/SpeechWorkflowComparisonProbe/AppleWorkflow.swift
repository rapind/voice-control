@preconcurrency import AVFoundation
import Foundation
import Speech

@available(macOS 26.0, *)
actor AppleResultCollector {
  private let startedAt: UInt64
  private var firstPreviewSeconds: Double?
  private var finalized = ""
  private var volatile = ""

  init(startedAt: UInt64) {
    self.startedAt = startedAt
  }

  func accept(_ result: SpeechTranscriber.Result) {
    if firstPreviewSeconds == nil {
      firstPreviewSeconds = seconds(
        from: startedAt,
        to: DispatchTime.now().uptimeNanoseconds
      )
    }
    let text = String(result.text.characters)
    if result.isFinal {
      finalized += text
      volatile = ""
    } else {
      volatile = text
    }
  }

  func output() -> (Double?, String) {
    (firstPreviewSeconds, finalized + volatile)
  }
}

@available(macOS 26.0, *)
struct AppleWorkflow {
  private let locale: Locale

  init() async throws {
    guard SpeechTranscriber.isAvailable else {
      throw ProbeError("SpeechTranscriber is unavailable on this Mac")
    }
    guard
      let locale = await SpeechTranscriber.supportedLocale(
        equivalentTo: Locale(identifier: "en-US")
      )
    else {
      throw ProbeError("SpeechTranscriber does not support en-US")
    }
    self.locale = locale

    let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
      try await request.downloadAndInstall()
    }
  }

  func run(prompt: CorpusPrompt, fileURL: URL) async throws -> WorkflowResult {
    let audioFile = try AVAudioFile(forReading: fileURL)
    let format = audioFile.processingFormat
    let audioDuration = Double(audioFile.length) / format.sampleRate
    let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    guard
      let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
        compatibleWith: [transcriber]
      )
    else {
      throw ProbeError("SpeechAnalyzer has no compatible audio format")
    }

    let pair = AsyncStream.makeStream(of: AnalyzerInput.self, bufferingPolicy: .unbounded)
    try await analyzer.start(inputSequence: pair.stream)
    let startedAt = DispatchTime.now().uptimeNanoseconds
    let collector = AppleResultCollector(startedAt: startedAt)
    let resultTask = Task {
      for try await result in transcriber.results {
        await collector.accept(result)
      }
    }
    let converter = try AppleBufferConverter(
      inputFormat: format,
      outputFormat: analyzerFormat
    )

    while audioFile.framePosition < audioFile.length {
      let remaining = audioFile.length - audioFile.framePosition
      let frameCount = AVAudioFrameCount(min(4_096, remaining))
      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        throw ProbeError("Could not allocate an Apple input buffer")
      }
      try audioFile.read(into: buffer, frameCount: frameCount)
      pair.continuation.yield(AnalyzerInput(buffer: try converter.convert(buffer)))
      let duration = Double(buffer.frameLength) / format.sampleRate
      try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    }

    let audioEndedAt = DispatchTime.now().uptimeNanoseconds
    pair.continuation.finish()
    try await analyzer.finalizeAndFinishThroughEndOfInput()
    _ = try await resultTask.value
    let finishedAt = DispatchTime.now().uptimeNanoseconds
    let output = await collector.output()
    return WorkflowResult(
      engine: "apple-progressive",
      promptID: prompt.id,
      audioDurationSeconds: audioDuration,
      firstPreviewSeconds: output.0,
      finalizationSeconds: seconds(from: audioEndedAt, to: finishedAt),
      totalSeconds: seconds(from: startedAt, to: finishedAt),
      transcript: output.1
    )
  }
}

@available(macOS 26.0, *)
private final class AppleBufferConverter {
  private let converter: AVAudioConverter
  private let outputFormat: AVAudioFormat

  init(inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) throws {
    guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
      throw ProbeError("Could not create an Apple Speech audio converter")
    }
    self.converter = converter
    self.outputFormat = outputFormat
  }

  func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
    let ratio = outputFormat.sampleRate / input.format.sampleRate
    let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio)) + 1
    guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
      throw ProbeError("Could not allocate a converted Apple Speech buffer")
    }

    var supplied = false
    var conversionError: NSError?
    let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
      if supplied {
        inputStatus.pointee = .noDataNow
        return nil
      }
      supplied = true
      inputStatus.pointee = .haveData
      return input
    }
    if let conversionError { throw conversionError }
    guard status == .haveData || status == .inputRanDry else {
      throw ProbeError("Apple Speech audio conversion failed with status \(status.rawValue)")
    }
    return output
  }
}
