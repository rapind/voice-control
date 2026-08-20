import AVFoundation
import Foundation
import Testing

@testable import VoiceControlDaemon

@Test func separatelySpokenSubmitPhraseUsesTheLiveTranscriptBeforeThatBurst() {
  var transcript = LiveTranscriptCheckpoint()
  transcript.update("store this value as an array")
  transcript.beginSeparatedSpeechBurst()
  transcript.update("store this value as an array Sunday")

  #expect(
    transcript.textForSubmission(excludingLatestSeparatedBurst: true)
      == "store this value as an array"
  )
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
  private(set) var transcribedURLs: [URL] = []

  init(liveTranscriptIsAuthoritative: Bool = false) {
    self.liveTranscriptIsAuthoritative = liveTranscriptIsAuthoritative
  }

  func prepare() async throws {}

  func startLiveTranscription(
    input: LiveAudioBufferSink,
    onUpdate: @escaping @MainActor @Sendable (String) -> Void,
    onError: @escaping @MainActor @Sendable (String) -> Void
  ) async throws {}

  func stopLiveTranscription() async {
    stopCount += 1
  }

  func transcribe(fileURL: URL) async throws -> String {
    transcribedURLs.append(fileURL)
    return "transcript"
  }

  func updateContextualStrings(_ contextualStrings: [String]) async {}
}
