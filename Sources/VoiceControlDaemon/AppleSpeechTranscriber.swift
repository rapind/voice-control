@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import OSLog
import Speech

@available(macOS 26.0, *)
actor AppleSpeechTranscriber: PromptTranscriberBackend {
  nonisolated let name = "Apple Speech progressive transcription"
  nonisolated let liveTranscriptIsAuthoritative = true
  private let logger = Logger(
    subsystem: "com.daverapin.voice-control-prototype",
    category: "AppleSpeechTranscriber"
  )

  private var locale: Locale?
  private var analyzer: SpeechAnalyzer?
  private var contextualStrings: [String]
  private var liveInput: LiveAudioBufferSink?
  private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
  private var feederTask: Task<Void, Never>?
  private var resultTask: Task<Void, Never>?
  private var finalizedText = ""
  private var volatileText = ""
  private var finalizedResults: [TimedTranscript] = []
  private var volatileResult: TimedTranscript?
  private var latestResultAudioEnd: TimeInterval?
  private var progressiveResultWaiter: CheckedContinuation<Bool, Never>?
  private var progressiveResultTarget: TimeInterval?
  private var progressiveResultTimeoutTask: Task<Void, Never>?
  private var liveError: (any Error)?
  private var generation = 0

  init(contextualStrings: [String]) {
    self.contextualStrings = contextualStrings
  }

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
    onUpdate: @escaping @MainActor @Sendable (LiveTranscriptionUpdate) -> Void,
    onError: @escaping @MainActor @Sendable (String) -> Void
  ) async throws {
    await stopLiveTranscription()
    guard let locale else {
      throw AppleSpeechError("Apple Speech is not prepared")
    }

    let generation = self.generation
    finalizedText = ""
    volatileText = ""
    finalizedResults = []
    volatileResult = nil
    latestResultAudioEnd = nil
    liveError = nil
    let transcriber = SpeechTranscriber(
      locale: locale,
      preset: .timeIndexedProgressiveTranscription
    )
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    let context = AnalysisContext()
    context.contextualStrings[.general] = contextualStrings
    try await analyzer.setContext(context)
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
          let timedTranscript = TimedTranscript(text: result.text, range: result.range)
          if result.isFinal {
            finalizedText += text
            volatileText = ""
            finalizedResults.append(timedTranscript)
            volatileResult = nil
          } else {
            volatileText = text
            volatileResult = timedTranscript
          }
          let resultEnd = result.range.end.seconds
          if resultEnd.isFinite {
            latestResultAudioEnd = max(latestResultAudioEnd ?? 0, resultEnd)
          }
          resumeProgressiveResultWaiterIfCovered()
          await onUpdate(
            LiveTranscriptionUpdate(
              text: finalizedText + volatileText,
              audioEndTime: latestResultAudioEnd
            )
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

    feederTask = Task {
      do {
        let converter = try AppleSpeechBufferConverter(
          inputFormat: nil,
          outputFormat: analyzerFormat
        )
        var convertedFramePosition: Int64 = 0
        let timeScale = CMTimeScale(analyzerFormat.sampleRate.rounded())
        for await buffer in input.stream {
          try Task.checkCancellation()
          guard generation == self.generation else { return }
          let converted = try converter.convert(buffer)
          guard converted.frameLength > 0 else { continue }
          let bufferStartTime = CMTime(
            value: convertedFramePosition,
            timescale: timeScale
          )
          inputBuilder?.yield(
            AnalyzerInput(buffer: converted, bufferStartTime: bufferStartTime)
          )
          convertedFramePosition += Int64(converted.frameLength)
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

  func updateContextualStrings(_ contextualStrings: [String]) async {
    self.contextualStrings = contextualStrings
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

  func finishLiveTranscription(
    _ request: LiveTranscriptionFinishRequest
  ) async throws -> LiveTranscriptionFinishResult {
    liveInput?.finish()
    await feederTask?.value
    feederTask = nil
    inputBuilder?.finish()
    inputBuilder = nil

    let covered: Bool
    if let target = request.waitThroughAudioTime {
      covered = await waitForProgressiveResult(through: target)
      logger.notice(
        "Progressive drain target=\(target, privacy: .public)s result-end=\(self.latestResultAudioEnd ?? -1, privacy: .public)s covered=\(covered, privacy: .public)"
      )
    } else {
      covered = true
    }

    let text = progressiveText(before: request.includeAudioBeforeTime)
    let error = liveError
    await analyzer?.cancelAndFinishNow()
    resultTask?.cancel()
    await resultTask?.value
    clearSession()
    if let error { throw error }
    return LiveTranscriptionFinishResult(text: text)
  }

  private func clearSession() {
    progressiveResultTimeoutTask?.cancel()
    progressiveResultTimeoutTask = nil
    progressiveResultTarget = nil
    progressiveResultWaiter?.resume(returning: false)
    progressiveResultWaiter = nil
    analyzer = nil
    liveInput = nil
    inputBuilder = nil
    feederTask = nil
    resultTask = nil
    finalizedText = ""
    volatileText = ""
    finalizedResults = []
    volatileResult = nil
    latestResultAudioEnd = nil
    liveError = nil
  }

  private func waitForProgressiveResult(through target: TimeInterval) async -> Bool {
    guard !progressiveResultCovers(target) else { return true }
    return await withCheckedContinuation { continuation in
      progressiveResultTarget = target
      progressiveResultWaiter = continuation
      progressiveResultTimeoutTask?.cancel()
      progressiveResultTimeoutTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        await self?.resumeProgressiveResultWaiter(covered: false)
      }
    }
  }

  private func progressiveResultCovers(_ target: TimeInterval) -> Bool {
    // Audio-level speech boundaries include the tail of the capture buffer.
    // Speech's word range normally ends a little earlier than that boundary.
    return ProgressiveResultCoverage.covers(
      audioEndTime: latestResultAudioEnd,
      target: target
    )
  }

  private func resumeProgressiveResultWaiterIfCovered() {
    guard
      let progressiveResultTarget,
      progressiveResultCovers(progressiveResultTarget)
    else { return }
    resumeProgressiveResultWaiter(covered: true)
  }

  private func resumeProgressiveResultWaiter(covered: Bool) {
    progressiveResultTimeoutTask?.cancel()
    progressiveResultTimeoutTask = nil
    progressiveResultTarget = nil
    let waiter = progressiveResultWaiter
    progressiveResultWaiter = nil
    waiter?.resume(returning: covered)
  }

  private func progressiveText(before cutoff: TimeInterval?) -> String {
    let results = finalizedResults + [volatileResult].compactMap { $0 }
    return results.map { result in
      guard let cutoff else { return String(result.text.characters) }
      let includedTime = CMTimeRange(
        start: .zero,
        duration: CMTime(seconds: cutoff, preferredTimescale: 48_000)
      )
      guard
        let range = result.text.rangeOfAudioTimeRangeAttributes(
          intersecting: includedTime
        )
      else {
        return result.range.start.seconds < cutoff ? String(result.text.characters) : ""
      }
      return String(result.text[range].characters)
    }.joined()
  }
}

@available(macOS 26.0, *)
private struct TimedTranscript: Sendable {
  let text: AttributedString
  let range: CMTimeRange
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
