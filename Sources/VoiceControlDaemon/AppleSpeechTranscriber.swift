@preconcurrency import AVFoundation
import Foundation
import Speech

@available(macOS 26.0, *)
actor AppleSpeechTranscriber: PromptTranscriberBackend {
  nonisolated let name = "Apple Speech progressive transcription"

  private var locale: Locale?
  private var analyzer: SpeechAnalyzer?
  private var liveInput: LiveAudioBufferSink?
  private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
  private var feederTask: Task<Void, Never>?
  private var resultTask: Task<Void, Never>?
  private var finalizedText = ""
  private var volatileText = ""
  private var liveError: (any Error)?
  private var generation = 0

  func prepare() async throws {
    guard SpeechTranscriber.isAvailable else {
      throw AppleSpeechError("SpeechTranscriber is unavailable on this Mac")
    }
    guard
      let locale = await SpeechTranscriber.supportedLocale(
        equivalentTo: Locale(identifier: "en-US")
      )
    else {
      throw AppleSpeechError("SpeechTranscriber does not support en-US on this Mac")
    }

    let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
      try await request.downloadAndInstall()
    }
    guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
      throw AppleSpeechError("The Apple en-US speech model is not installed")
    }
    self.locale = locale
  }

  func startLiveTranscription(
    input: LiveAudioBufferSink,
    onUpdate: @escaping @MainActor @Sendable (String) -> Void,
    onError: @escaping @MainActor @Sendable (String) -> Void
  ) async throws {
    await stopLiveTranscription()
    guard let locale else {
      throw AppleSpeechError("Apple Speech is not prepared")
    }

    let generation = self.generation
    finalizedText = ""
    volatileText = ""
    liveError = nil
    let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    guard
      let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
        compatibleWith: [transcriber]
      )
    else {
      throw AppleSpeechError("SpeechAnalyzer has no compatible audio format")
    }

    let pair = AsyncStream.makeStream(
      of: AnalyzerInput.self,
      bufferingPolicy: .unbounded
    )
    self.analyzer = analyzer
    self.liveInput = input
    inputBuilder = pair.continuation

    resultTask = Task {
      do {
        for try await result in transcriber.results {
          try Task.checkCancellation()
          guard generation == self.generation else { return }
          let text = String(result.text.characters)
          if result.isFinal {
            finalizedText += text
            volatileText = ""
          } else {
            volatileText = text
          }
          await onUpdate(finalizedText + volatileText)
        }
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled, generation == self.generation else { return }
        liveError = error
        await onError(error.localizedDescription)
      }
    }

    feederTask = Task {
      do {
        let converter = try AppleSpeechBufferConverter(
          inputFormat: nil,
          outputFormat: analyzerFormat
        )
        for await buffer in input.stream {
          try Task.checkCancellation()
          guard generation == self.generation else { return }
          inputBuilder?.yield(
            AnalyzerInput(buffer: try converter.convert(buffer))
          )
        }
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled, generation == self.generation else { return }
        liveError = error
        await onError(error.localizedDescription)
      }
    }

    do {
      try await analyzer.start(inputSequence: pair.stream)
    } catch {
      await stopLiveTranscription()
      throw error
    }
  }

  func stopLiveTranscription() async {
    generation += 1
    liveInput?.finish()
    feederTask?.cancel()
    await feederTask?.value
    inputBuilder?.finish()
    await analyzer?.cancelAndFinishNow()
    resultTask?.cancel()
    await resultTask?.value
    clearSession()
  }

  func transcribe(fileURL: URL) async throws -> String {
    guard let analyzer else {
      return try await transcribeFile(fileURL)
    }

    await feederTask?.value
    feederTask = nil
    inputBuilder?.finish()
    inputBuilder = nil
    do {
      try await analyzer.finalizeAndFinishThroughEndOfInput()
      await resultTask?.value
      resultTask = nil
      let text = finalizedText
      let error = liveError
      clearSession()
      if let error { throw error }
      if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return text
      }
      return try await transcribeFile(fileURL)
    } catch {
      await analyzer.cancelAndFinishNow()
      resultTask?.cancel()
      await resultTask?.value
      clearSession()
      throw error
    }
  }

  private func transcribeFile(_ fileURL: URL) async throws -> String {
    guard let locale else {
      throw AppleSpeechError("Apple Speech is not prepared")
    }
    let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
    let audioFile = try AVAudioFile(forReading: fileURL)
    async let transcript: String = {
      var text = ""
      for try await result in transcriber.results {
        text += String(result.text.characters)
      }
      return text
    }()

    let analyzer = SpeechAnalyzer(modules: [transcriber])
    if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
      try await analyzer.finalizeAndFinish(through: lastSample)
    } else {
      await analyzer.cancelAndFinishNow()
    }
    return try await transcript
  }

  private func clearSession() {
    analyzer = nil
    liveInput = nil
    inputBuilder = nil
    feederTask = nil
    resultTask = nil
    finalizedText = ""
    volatileText = ""
    liveError = nil
  }
}

@available(macOS 26.0, *)
private final class AppleSpeechBufferConverter {
  private let outputFormat: AVAudioFormat
  private var converter: AVAudioConverter?

  init(inputFormat: AVAudioFormat?, outputFormat: AVAudioFormat) throws {
    self.outputFormat = outputFormat
    if let inputFormat {
      converter = AVAudioConverter(from: inputFormat, to: outputFormat)
    }
  }

  func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
    if converter?.inputFormat != input.format {
      converter = AVAudioConverter(from: input.format, to: outputFormat)
    }
    guard let converter else {
      throw AppleSpeechError("Could not create the Apple Speech audio converter")
    }

    let ratio = outputFormat.sampleRate / input.format.sampleRate
    let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio)) + 1
    guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
      throw AppleSpeechError("Could not allocate a converted Apple Speech buffer")
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
      throw AppleSpeechError("Apple Speech audio conversion failed with status \(status.rawValue)")
    }
    return output
  }
}

@available(macOS 26.0, *)
struct AppleSpeechError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}
