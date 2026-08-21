import AVFoundation
import Foundation
import Testing

@testable import VoiceControlDaemon

@Test func separatelySpokenSubmitPhraseUsesTheLiveTranscriptBeforeThatBurst() {
  var transcript = LiveTranscriptCheckpoint()
  transcript.update("store this value as an array", audioEndTime: 3.9)
  transcript.beginSeparatedSpeechBurst()
  transcript.update("store this value as an array Sunday", audioEndTime: 5.2)

  #expect(
    transcript.textForSubmission(excludingLatestSeparatedBurst: true)
      == "store this value as an array"
  )
  #expect(transcript.audioEndTimeForSubmission(excludingLatestSeparatedBurst: true) == 3.9)
}

@Test func silenceSubmissionUsesTheLatestLiveRevision() {
  var transcript = LiveTranscriptCheckpoint()
  transcript.update("store this value as a Norway")
  transcript.update("store this value as an array")

  #expect(
    transcript.textForSubmission(excludingLatestSeparatedBurst: false)
      == "store this value as an array"
  )
}

@Test func emptyLiveTranscriptFallsBackToFileTranscription() async throws {
  let backend = PromptTranscriberBackendSpy(liveTranscriptIsAuthoritative: true)
  let transcriber = PromptTranscriber(backend: backend)
  let fileURL = URL(fileURLWithPath: "/tmp/trimmed-prompt.wav")

  _ = try await transcriber.transcribe(
    fileURL: fileURL,
    preferredLiveTranscript: nil
  )

  #expect(await backend.stopCount == 1)
  #expect(await backend.transcribedURLs == [fileURL])
}

@Test func authoritativeLiveTranscriptSkipsFinalFileTranscription() async throws {
  let backend = PromptTranscriberBackendSpy(liveTranscriptIsAuthoritative: true)
  let transcriber = PromptTranscriber(backend: backend)
  let fileURL = URL(fileURLWithPath: "/tmp/ignored-prompt.wav")

  let result = try await transcriber.transcribe(
    fileURL: fileURL,
    preferredLiveTranscript: "store this value as an array"
  )

  #expect(result == "store this value as an array")
  #expect(await backend.stopCount == 1)
  #expect(await backend.transcribedURLs.isEmpty)
}

@Test func authoritativeLiveTranscriptWaitsForPendingProgressiveResult() async throws {
  let backend = PromptTranscriberBackendSpy(
    liveTranscriptIsAuthoritative: true,
    completedLiveTranscript: "store these values as an array then iterate over the array"
  )
  let transcriber = PromptTranscriber(backend: backend)
  let fileURL = URL(fileURLWithPath: "/tmp/ignored-prompt.wav")

  let result = try await transcriber.transcribe(
    fileURL: fileURL,
    preferredLiveTranscript: "store these values as an array",
    preferredLiveTranscriptAudioEndTime: 3,
    liveTranscriptionRequest: LiveTranscriptionFinishRequest(
      waitThroughAudioTime: 4.2,
      includeAudioBeforeTime: 5.0
    )
  )

  #expect(result == "store these values as an array then iterate over the array")
  #expect(await backend.finishedLiveTranscriptCutoffs == [4.2])
  #expect(await backend.transcribedURLs.isEmpty)
}

@Test func authoritativeLiveTranscriptPreservesTheVisiblePreviewWhenItAlreadyCoveredThePrompt()
  async throws
{
  let backend = PromptTranscriberBackendSpy(
    liveTranscriptIsAuthoritative: true,
    completedLiveTranscript: "Are we committed and pushed"
  )
  let transcriber = PromptTranscriber(backend: backend)
  let fileURL = URL(fileURLWithPath: "/tmp/ignored-prompt.wav")

  let result = try await transcriber.transcribe(
    fileURL: fileURL,
    preferredLiveTranscript: "Are we committed and pushed?",
    preferredLiveTranscriptAudioEndTime: 4.1,
    liveTranscriptionRequest: LiveTranscriptionFinishRequest(
      waitThroughAudioTime: 4.2,
      includeAudioBeforeTime: nil
    )
  )

  #expect(result == "Are we committed and pushed?")
  #expect(await backend.finishedLiveTranscriptCutoffs == [nil])
  #expect(await backend.transcribedURLs.isEmpty)
}

@Test func authoritativeLiveTranscriptFallsBackToFileWhenProgressiveDrainTimesOut() async throws {
  let backend = PromptTranscriberBackendSpy(
    liveTranscriptIsAuthoritative: true,
    completedLiveTranscript: "the incomplete progressive result",
    completedLiveTranscriptCoveredRequestedAudio: false
  )
  let transcriber = PromptTranscriber(backend: backend)
  let fileURL = URL(fileURLWithPath: "/tmp/complete-prompt.wav")

  let result = try await transcriber.transcribe(
    fileURL: fileURL,
    preferredLiveTranscript: "an older incomplete preview",
    liveTranscriptionRequest: LiveTranscriptionFinishRequest(
      waitThroughAudioTime: 12.4,
      includeAudioBeforeTime: nil
    )
  )

  #expect(result == "transcript")
  #expect(await backend.finishedLiveTranscriptCutoffs == [12.4])
  #expect(await backend.transcribedURLs == [fileURL])
}

@Test func nonAuthoritativeBackendKeepsItsFinalFileTranscription() async throws {
  let backend = PromptTranscriberBackendSpy()
  let transcriber = PromptTranscriber(backend: backend)
  let fileURL = URL(fileURLWithPath: "/tmp/parakeet-prompt.wav")

  let result = try await transcriber.transcribe(
    fileURL: fileURL,
    preferredLiveTranscript: "rolling preview"
  )

  #expect(result == "transcript")
  #expect(await backend.stopCount == 0)
  #expect(await backend.transcribedURLs == [fileURL])
}

private actor PromptTranscriberBackendSpy: PromptTranscriberBackend {
  nonisolated let name = "spy"
  nonisolated let liveTranscriptIsAuthoritative: Bool
  private(set) var stopCount = 0
  private(set) var finishedLiveTranscriptCutoffs: [TimeInterval?] = []
  private(set) var transcribedURLs: [URL] = []
  private let completedLiveTranscript: String?
  private let completedLiveTranscriptCoveredRequestedAudio: Bool

  init(
    liveTranscriptIsAuthoritative: Bool = false,
    completedLiveTranscript: String? = nil,
    completedLiveTranscriptCoveredRequestedAudio: Bool = true
  ) {
    self.liveTranscriptIsAuthoritative = liveTranscriptIsAuthoritative
    self.completedLiveTranscript = completedLiveTranscript
    self.completedLiveTranscriptCoveredRequestedAudio =
      completedLiveTranscriptCoveredRequestedAudio
  }

  func prepare() async throws {}

  func startLiveTranscription(
    input: LiveAudioBufferSink,
    onUpdate: @escaping @MainActor @Sendable (LiveTranscriptionUpdate) -> Void,
    onError: @escaping @MainActor @Sendable (String) -> Void
  ) async throws {}

  func stopLiveTranscription() async {
    stopCount += 1
  }

  func finishLiveTranscription(
    _ request: LiveTranscriptionFinishRequest
  ) async throws -> LiveTranscriptionFinishResult {
    finishedLiveTranscriptCutoffs.append(request.waitThroughAudioTime)
    stopCount += 1
    return LiveTranscriptionFinishResult(
      text: completedLiveTranscript,
      coveredRequestedAudio: completedLiveTranscriptCoveredRequestedAudio
    )
  }

  func transcribe(fileURL: URL) async throws -> String {
    transcribedURLs.append(fileURL)
    return "transcript"
  }

  func updateContextualStrings(_ contextualStrings: [String]) async {}
}
