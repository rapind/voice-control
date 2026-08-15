@preconcurrency import AVFoundation
import Foundation
import Speech

@available(macOS 26.0, *)
actor ResultCollector {
  private let startedAt: UInt64
  private var firstResultSeconds: Double?
  private var finalized = ""
  private var volatile = ""

  init(startedAt: UInt64) {
    self.startedAt = startedAt
  }

  func accept(_ result: SpeechTranscriber.Result) {
    if firstResultSeconds == nil {
      firstResultSeconds = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000_000
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
    (firstResultSeconds, finalized + volatile)
  }
}

@available(macOS 26.0, *)
struct ProbeResult: Codable {
  let file: String
  let firstResultSeconds: Double?
  let transcript: String
}

@available(macOS 26.0, *)
final class BufferConverter {
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
      throw ProbeError("Could not allocate a converted audio buffer")
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

struct ProbeError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}

@main
struct AppleLivePreviewProbe {
  static func main() async throws {
    guard #available(macOS 26.0, *) else {
      throw ProbeError("AppleLivePreviewProbe requires macOS 26")
    }
    guard !CommandLine.arguments.dropFirst().isEmpty else {
      throw ProbeError("Pass one or more recorded audio files")
    }
    guard
      let locale = await SpeechTranscriber.supportedLocale(
        equivalentTo: Locale(identifier: "en-US")
      )
    else {
      throw ProbeError("SpeechTranscriber does not support en-US")
    }

    for path in CommandLine.arguments.dropFirst() {
      let fileURL = URL(fileURLWithPath: path)
      let audioFile = try AVAudioFile(forReading: fileURL)
      let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
      if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
        try await request.downloadAndInstall()
      }
      guard
        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
          compatibleWith: [transcriber]
        )
      else {
        throw ProbeError("SpeechAnalyzer has no compatible audio format")
      }

      let analyzer = SpeechAnalyzer(modules: [transcriber])
      let pair = AsyncStream.makeStream(of: AnalyzerInput.self, bufferingPolicy: .unbounded)
      let startedAt = DispatchTime.now().uptimeNanoseconds
      let collector = ResultCollector(startedAt: startedAt)
      let resultTask = Task {
        for try await result in transcriber.results {
          await collector.accept(result)
        }
      }
      try await analyzer.start(inputSequence: pair.stream)

      let format = audioFile.processingFormat
      let converter = try BufferConverter(inputFormat: format, outputFormat: analyzerFormat)
      while audioFile.framePosition < audioFile.length {
        let remaining = audioFile.length - audioFile.framePosition
        let frameCount = AVAudioFrameCount(min(4_096, remaining))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
          throw ProbeError("Could not allocate an input buffer")
        }
        try audioFile.read(into: buffer, frameCount: frameCount)
        pair.continuation.yield(AnalyzerInput(buffer: try converter.convert(buffer)))
        let duration = Double(buffer.frameLength) / format.sampleRate
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
      }

      pair.continuation.finish()
      try await analyzer.finalizeAndFinishThroughEndOfInput()
      _ = try await resultTask.value
      let output = await collector.output()
      let result = ProbeResult(
        file: fileURL.lastPathComponent,
        firstResultSeconds: output.0,
        transcript: output.1
      )
      let data = try JSONEncoder().encode(result)
      print(String(decoding: data, as: UTF8.self))
    }
  }
}
