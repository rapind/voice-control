import AVFoundation
import Foundation
import Testing

@testable import VoiceControlDaemon

@Test func discardsLiveTranscriptionBeforeReadingTrimmedRecording() async throws {
  let backend = PromptTranscriberBackendSpy()
  let transcriber = PromptTranscriber(backend: backend)
  let fileURL = URL(fileURLWithPath: "/tmp/trimmed-prompt.wav")

  _ = try await transcriber.transcribe(
    fileURL: fileURL,
    discardLiveTranscript: true
  )

  #expect(await backend.stopCount == 1)
  #expect(await backend.transcribedURLs == [fileURL])
}

private actor PromptTranscriberBackendSpy: PromptTranscriberBackend {
  nonisolated let name = "spy"
  private(set) var stopCount = 0
  private(set) var transcribedURLs: [URL] = []

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
