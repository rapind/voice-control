@preconcurrency import AVFoundation
import FluidAudio
import Foundation

protocol PromptTranscriberBackend: Sendable {
  var name: String { get }
  var liveTranscriptIsAuthoritative: Bool { get }

  func prepare() async throws
  func startLiveTranscription(
    input: LiveAudioBufferSink,
    onUpdate: @escaping @MainActor @Sendable (LiveTranscriptionUpdate) -> Void,
    onError: @escaping @MainActor @Sendable (String) -> Void
  ) async throws
  func stopLiveTranscription() async
  func finishLiveTranscription(
    _ request: LiveTranscriptionFinishRequest
  ) async throws -> LiveTranscriptionFinishResult
  func transcribe(fileURL: URL) async throws -> String
  func updateContextualStrings(_ contextualStrings: [String]) async
}

extension PromptTranscriberBackend {
  var liveTranscriptIsAuthoritative: Bool { false }

  func finishLiveTranscription(
    _ request: LiveTranscriptionFinishRequest
  ) async throws -> LiveTranscriptionFinishResult {
    await stopLiveTranscription()
    return LiveTranscriptionFinishResult(text: nil)
  }

  func transcribe(fileURL: URL) async throws -> String {
    throw PromptTranscriptionError("\(name) does not support full-file transcription")
  }
}

struct LiveTranscriptionFinishRequest: Equatable, Sendable {
  let waitThroughAudioTime: TimeInterval?
  let includeAudioBeforeTime: TimeInterval?
}

struct LiveTranscriptionFinishResult: Equatable, Sendable {
  let text: String?
}

struct LiveTranscriptionUpdate: Equatable, Sendable {
  let text: String
  let audioEndTime: TimeInterval?
}

enum ProgressiveResultCoverage {
  private static let audioTailTolerance: TimeInterval = 0.25

  static func covers(audioEndTime: TimeInterval?, target: TimeInterval) -> Bool {
    guard let audioEndTime, audioEndTime.isFinite, target.isFinite else { return false }
    return audioEndTime + audioTailTolerance >= target
  }
}

struct LiveTranscriptCheckpoint {
  private(set) var latestText = ""
  private var latestAudioEndTime: TimeInterval?
  private var textBeforeLatestSeparatedBurst: String?
  private var audioEndTimeBeforeLatestSeparatedBurst: TimeInterval?

  mutating func update(_ text: String, audioEndTime: TimeInterval? = nil) {
    latestText = text
    latestAudioEndTime = audioEndTime
  }

  mutating func beginSeparatedSpeechBurst() {
    textBeforeLatestSeparatedBurst = latestText
    audioEndTimeBeforeLatestSeparatedBurst = latestAudioEndTime
  }

  func textForSubmission(excludingLatestSeparatedBurst: Bool) -> String {
    if excludingLatestSeparatedBurst, let textBeforeLatestSeparatedBurst {
      return textBeforeLatestSeparatedBurst
    }
    return latestText
  }

  func audioEndTimeForSubmission(excludingLatestSeparatedBurst: Bool) -> TimeInterval? {
    if excludingLatestSeparatedBurst {
      return audioEndTimeBeforeLatestSeparatedBurst
    }
    return latestAudioEndTime
  }
}

final class PromptTranscriber {
  let name: String

  private let backend: any PromptTranscriberBackend

  init(contextualStrings: [String]) {
    if #available(macOS 26.0, *) {
      let backend = AppleSpeechTranscriber(contextualStrings: contextualStrings)
      self.backend = backend
      self.name = backend.name
    } else {
      let backend = ParakeetTranscriber()
      self.backend = backend
      self.name = backend.name
    }
  }

  init(backend: any PromptTranscriberBackend) {
    self.backend = backend
    self.name = backend.name
  }

  func prepare() async throws {
    try await backend.prepare()
  }

  func updateContextualStrings(_ contextualStrings: [String]) async {
    await backend.updateContextualStrings(contextualStrings)
  }

  func startLiveTranscription(
    input: LiveAudioBufferSink,
    onUpdate: @escaping @MainActor @Sendable (LiveTranscriptionUpdate) -> Void,
    onError: @escaping @MainActor @Sendable (String) -> Void
  ) async throws {
    try await backend.startLiveTranscription(
      input: input,
      onUpdate: onUpdate,
      onError: onError
    )
  }

  func stopLiveTranscription() async {
    await backend.stopLiveTranscription()
  }

  func transcribe(
    fileURL: URL,
    preferredLiveTranscript: String?,
    preferredLiveTranscriptAudioEndTime: TimeInterval? = nil,
    liveTranscriptionRequest: LiveTranscriptionFinishRequest? = nil
  ) async throws -> String {
    if backend.liveTranscriptIsAuthoritative {
      let preferredText = preferredLiveTranscript?.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      let preferredTranscriptCoversRequest: Bool
      if let target = liveTranscriptionRequest?.waitThroughAudioTime {
        preferredTranscriptCoversRequest =
          preferredText?.isEmpty == false
          && ProgressiveResultCoverage.covers(
            audioEndTime: preferredLiveTranscriptAudioEndTime,
            target: target
          )
      } else {
        preferredTranscriptCoversRequest = preferredText?.isEmpty == false
      }
      let finishRequest: LiveTranscriptionFinishRequest
      if preferredTranscriptCoversRequest {
        finishRequest = LiveTranscriptionFinishRequest(
          waitThroughAudioTime: nil,
          includeAudioBeforeTime: liveTranscriptionRequest?.includeAudioBeforeTime
        )
      } else {
        finishRequest =
          liveTranscriptionRequest
          ?? LiveTranscriptionFinishRequest(
            waitThroughAudioTime: nil,
            includeAudioBeforeTime: nil
          )
      }
      let completedLiveTranscript = try await backend.finishLiveTranscription(
        finishRequest
      )
      if preferredTranscriptCoversRequest, let preferredText {
        return preferredText
      }
      if let text = completedLiveTranscript.text {
        let liveTranscript = text.trimmingCharacters(
          in: .whitespacesAndNewlines
        )
        if !liveTranscript.isEmpty {
          return liveTranscript
        }
      }
      if let preferredLiveTranscript {
        let liveTranscript = preferredLiveTranscript.trimmingCharacters(
          in: .whitespacesAndNewlines
        )
        if !liveTranscript.isEmpty {
          return liveTranscript
        }
      }
      throw PromptTranscriptionError("Apple Speech returned no usable live transcript")
    }
    return try await backend.transcribe(fileURL: fileURL)
  }
}

struct PromptTranscriptionError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}

actor ParakeetTranscriber: PromptTranscriberBackend {
  private var manager: AsrManager?
  private var models: AsrModels?
  private var liveManager: AsrManager?
  private var liveInput: LiveAudioBufferSink?
  private var liveInputTask: Task<Void, Never>?
  private var liveGeneration = 0
  nonisolated let name = "local Parakeet v3 via FluidAudio"

  func prepare() async throws {
    let cacheDirectory = AsrModels.defaultCacheDirectory(for: .v3)
    guard AsrModels.modelsExist(at: cacheDirectory, version: .v3) else {
      throw ParakeetError(
        "No cached Parakeet v3 model was found at \(cacheDirectory.path). "
          + "Open TypeWhisper and load Parakeet once before starting this prototype."
      )
    }

    let models = try await AsrModels.load(
      from: cacheDirectory,
      version: .v3
    )
    let manager = AsrManager(config: .default)
    try await manager.loadModels(models)
    self.models = models
    self.manager = manager
  }

  func updateContextualStrings(_ contextualStrings: [String]) async {}

  func startLiveTranscription(
    input: LiveAudioBufferSink,
    onUpdate: @escaping @MainActor @Sendable (LiveTranscriptionUpdate) -> Void,
    onError: @escaping @MainActor @Sendable (String) -> Void
  ) async throws {
    await stopLiveTranscription()
    let generation = liveGeneration
    guard let models else {
      throw ParakeetError("Parakeet is not loaded")
    }

    let liveManager = AsrManager(config: .default)
    try await liveManager.loadModels(models)
    guard generation == liveGeneration else {
      await liveManager.cleanup()
      return
    }

    self.liveManager = liveManager
    liveInput = input
    liveInputTask = Task {
      let converter = AudioConverter()
      var samples: [Float] = []
      samples.reserveCapacity(16_000 * 30)
      let updateIntervalSamples = 24_000
      var nextUpdateSampleCount = updateIntervalSamples
      let decoderLayerCount = await liveManager.decoderLayerCount

      do {
        for await buffer in input.stream {
          try Task.checkCancellation()
          samples.append(contentsOf: try converter.resampleBuffer(buffer))
          guard samples.count >= nextUpdateSampleCount else { continue }
          nextUpdateSampleCount = samples.count + updateIntervalSamples

          var decoderState = TdtDecoderState.make(decoderLayers: decoderLayerCount)
          let result = try await liveManager.transcribe(
            samples,
            decoderState: &decoderState,
            language: .english
          )
          try Task.checkCancellation()
          guard generation == self.liveGeneration else { return }
          await onUpdate(LiveTranscriptionUpdate(text: result.text, audioEndTime: nil))
        }
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled, generation == self.liveGeneration else { return }
        await onError(error.localizedDescription)
      }
    }
  }

  func stopLiveTranscription() async {
    liveGeneration += 1
    let input = liveInput
    let inputTask = liveInputTask
    let liveManager = liveManager
    liveInput = nil
    liveInputTask = nil
    self.liveManager = nil

    input?.finish()
    inputTask?.cancel()
    await inputTask?.value
    await liveManager?.cleanup()
  }

  func transcribe(fileURL: URL) async throws -> String {
    await stopLiveTranscription()
    guard let manager else {
      throw ParakeetError("Parakeet is not loaded")
    }

    var decoderState = TdtDecoderState.make(
      decoderLayers: await manager.decoderLayerCount
    )
    let result = try await manager.transcribe(
      fileURL,
      decoderState: &decoderState,
      language: .english
    )
    return result.text
  }
}

final class LiveAudioBufferRouter: @unchecked Sendable {
  private let lock = NSLock()
  private var sink: LiveAudioBufferSink?

  func route(to sink: LiveAudioBufferSink) {
    lock.lock()
    let previous = self.sink
    self.sink = sink
    lock.unlock()
    previous?.finish()
  }

  func appendCopy(of buffer: AVAudioPCMBuffer) {
    lock.lock()
    let sink = sink
    lock.unlock()
    sink?.appendCopy(of: buffer)
  }

  func finish() {
    lock.lock()
    let sink = sink
    self.sink = nil
    lock.unlock()
    sink?.finish()
  }
}

final class LiveAudioBufferSink: @unchecked Sendable {
  let stream: AsyncStream<AVAudioPCMBuffer>

  private let lock = NSLock()
  private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

  init() {
    let pair = AsyncStream.makeStream(
      of: AVAudioPCMBuffer.self,
      bufferingPolicy: .unbounded
    )
    stream = pair.stream
    continuation = pair.continuation
  }

  func appendCopy(of buffer: AVAudioPCMBuffer) {
    lock.lock()
    let continuation = continuation
    lock.unlock()
    guard let continuation, let copy = buffer.streamingCopy() else { return }
    continuation.yield(copy)
  }

  func finish() {
    lock.lock()
    let continuation = continuation
    self.continuation = nil
    lock.unlock()
    continuation?.finish()
  }
}

extension AVAudioPCMBuffer {
  fileprivate func streamingCopy() -> AVAudioPCMBuffer? {
    guard
      let copy = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: frameLength
      )
    else {
      return nil
    }
    copy.frameLength = frameLength

    let sourceBuffers = UnsafeMutableAudioBufferListPointer(mutableAudioBufferList)
    let destinationBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
    guard sourceBuffers.count == destinationBuffers.count else { return nil }
    for index in sourceBuffers.indices {
      let source = sourceBuffers[index]
      guard let sourceData = source.mData, let destinationData = destinationBuffers[index].mData
      else {
        return nil
      }
      memcpy(destinationData, sourceData, Int(source.mDataByteSize))
      destinationBuffers[index].mDataByteSize = source.mDataByteSize
    }
    return copy
  }
}

struct ParakeetError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}
