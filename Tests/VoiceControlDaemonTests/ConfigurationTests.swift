import AVFoundation
import Foundation
import Testing

@testable import VoiceControlDaemon

@Test func acceptsLegacyTargetSetting() throws {
  let configuration = try Configuration.decodeTOML(
    Data(
      """
      target = "chatgpt"
      """.utf8
    )
  )

  #expect(!configuration.commandMappings(for: .chatGPT).isEmpty)
}

@Test func onlyFrontmostTargetCommandsAreParsed() throws {
  let configuration = try Configuration.decodeTOML(
    Data(
      """
      target = "chatgpt"

      [applications.ghostty.commands]
      new_chat = ["open terminal chat"]
      focus_1 = ["focus 1"]

      [applications.chatgpt.commands]
      new_chat = ["open app chat"]
      focus_1 = ["focus 1"]
      """.utf8
    )
  )

  #expect(
    ApplicationCommand.parse(
      "open app chat",
      wakePhrases: configuration.wakePhrases,
      mappings: configuration.commandMappings(for: .chatGPT)
    ) == .newChat
  )
  #expect(
    ApplicationCommand.parse(
      "open terminal chat",
      wakePhrases: configuration.wakePhrases,
      mappings: configuration.commandMappings(for: .chatGPT)
    ) == nil
  )
  #expect(
    ApplicationCommand.parse(
      "focus 1",
      wakePhrases: configuration.wakePhrases,
      mappings: configuration.commandMappings(for: .chatGPT)
    ) == .focusItem(1)
  )
  #expect(
    ApplicationCommand.parse(
      "focus ghost tee",
      wakePhrases: configuration.wakePhrases,
      mappings: configuration.commandMappings(for: .chatGPT)
    ) == .focus(.ghostty)
  )
}

@Test func commandsFollowFrontmostTargetInsteadOfConfiguredTarget() throws {
  let configuration = try Configuration.decodeTOML(
    Data(
      """
      target = "chatgpt"

      [applications.ghostty.commands]
      new_chat = ["open terminal chat"]

      [applications.chatgpt.commands]
      new_chat = ["open app chat"]
      """.utf8
    )
  )
  let mappings = configuration.commandMappings(for: .ghostty)

  #expect(
    ApplicationCommand.parse(
      "open terminal chat",
      wakePhrases: configuration.wakePhrases,
      mappings: mappings
    ) == .newChat
  )
  #expect(
    ApplicationCommand.parse(
      "open app chat",
      wakePhrases: configuration.wakePhrases,
      mappings: mappings
    ) == nil
  )
}

@Test func GhosttySessionControlsAreOnlyRecognizedInGhostty() throws {
  let configuration = try Configuration.decodeTOML(
    Data(
      """
      [applications.ghostty.commands]
      interrupt_session = ["quit session"]
      start_session = ["start session"]
      """.utf8
    )
  )
  let ghosttyMappings = configuration.commandMappings(for: .ghostty)

  #expect(
    ApplicationCommand.parse(
      "quit session",
      wakePhrases: configuration.wakePhrases,
      mappings: ghosttyMappings
    ) == .interruptSession
  )
  #expect(
    ApplicationCommand.parse(
      "start session",
      wakePhrases: configuration.wakePhrases,
      mappings: ghosttyMappings
    ) == .startSession
  )
  #expect(
    ApplicationCommand.parse(
      "restart session",
      wakePhrases: configuration.wakePhrases,
      mappings: ghosttyMappings
    ) == nil
  )
}

@Test func unsupportedFrontmostApplicationConsumesSafeGlobalCommands() throws {
  let configuration = try Configuration.decodeTOML(Data())
  let mappings = configuration.commandMappings(for: nil)

  #expect(
    ApplicationCommand.parse(
      "focus chat",
      wakePhrases: configuration.wakePhrases,

      mappings: mappings
    ) == .focus(.chatGPT)
  )
  #expect(
    ApplicationCommand.parse(
      "focus 1",
      wakePhrases: configuration.wakePhrases,
      mappings: mappings
    ) == .focusItem(1)
  )
}

@Test func vocabularyTermsJoinSpeechContext() throws {
  let configuration = try Configuration.decodeTOML(
    Data("vocabulary = [\"bean\"]".utf8)
  )

  #expect(configuration.contextualPhrases.contains("bean"))
}

@Test func chromeSupportsGlobalFocusAndPositionalCommands() throws {
  let configuration = try Configuration.decodeTOML(Data())

  #expect(ApplicationTarget.chrome.bundleIdentifiers == ["com.google.Chrome"])
  #expect(
    ApplicationCommand.parse(
      "focus chrome",
      wakePhrases: configuration.wakePhrases,
      mappings: configuration.commandMappings(for: nil)
    ) == .focus(.chrome)
  )
  #expect(
    ApplicationCommand.parse(
      "focus 1",
      wakePhrases: configuration.wakePhrases,
      mappings: configuration.commandMappings(for: .chrome)
    ) == .focusItem(1)
  )
}

@Test func recognizesSupportedFrontmostApplicationsByBundleIdentifier() {
  #expect(ApplicationTarget(bundleIdentifier: "com.mitchellh.ghostty") == .ghostty)
  #expect(ApplicationTarget(bundleIdentifier: "com.openai.codex") == .chatGPT)
  #expect(ApplicationTarget(bundleIdentifier: "com.google.Chrome") == .chrome)
  #expect(ApplicationTarget(bundleIdentifier: "com.apple.TextEdit") == nil)
}

@Test func positionalCommandsRequireASupportedFrontmostApplication() {
  #expect(ApplicationCommand.focusItem(1).target(frontmost: .ghostty) == .ghostty)
  #expect(ApplicationCommand.focusItem(1).target(frontmost: .chatGPT) == .chatGPT)
  #expect(ApplicationCommand.focusItem(1).target(frontmost: .chrome) == .chrome)
  #expect(ApplicationCommand.focusItem(1).target(frontmost: nil) == nil)
  #expect(ApplicationCommand.focus(.chrome).target(frontmost: nil) == .chrome)
}

@Test func parsesShortChatFocusAlias() throws {
  let configuration = try Configuration.decodeTOML(
    Data(
      """
      target = "ghostty"
      """.utf8
    )
  )

  #expect(
    ApplicationCommand.parse(
      "focus chat",
      wakePhrases: configuration.wakePhrases,
      mappings: configuration.commandMappings(for: .ghostty)
    ) == .focus(.chatGPT)
  )
  #expect(configuration.contextualPhrases.contains("focus chat"))
}

@Test func rejectsCommandsOutsideAnApplicationHierarchy() {
  let data = Data(
    """
    [commands]
    new_chat = ["new chat"]
    """.utf8
  )

  #expect(throws: ConfigurationError.self) {
    try Configuration.decodeTOML(data)
  }
}

@Test func speechContextIncludesCommandsForEverySupportedFrontmostTarget() throws {
  let configuration = try Configuration.decodeTOML(
    Data(
      """
      target = "chatgpt"

      [applications.ghostty.commands]
      focus = ["terminal only"]
      new_chat = ["terminal action"]

      [applications.chatgpt.commands]
      focus = ["app only"]
      new_chat = ["app action"]
      """.utf8
    )
  )

  #expect(configuration.contextualPhrases.contains("app only"))
  #expect(configuration.contextualPhrases.contains("terminal only"))
  #expect(configuration.contextualPhrases.contains("app action"))
  #expect(configuration.contextualPhrases.contains("terminal action"))
}

@Test func rejectsGhosttyOnlyNavigationCommandsForChatGPT() {
  let data = Data(
    """
    [applications.chatgpt.commands]
    next = ["focus next"]
    """.utf8
  )

  #expect(throws: ConfigurationError.self) {
    try Configuration.decodeTOML(data)
  }
}

@Test func decodesCustomPhrasesAndTiming() throws {
  let configuration = try Configuration.decodeTOML(
    Data(
      """
      wake = ["computer", "hey computer"]
      submit = ["do it"]
      cancel = ["never mind"]
      silence_seconds = 6.5
      silence_threshold_db = -38
      maximum_recording_seconds = 120

      [applications.ghostty.commands]
      new_chat = ["make a chat"]
      """.utf8
    )
  )

  #expect(configuration.wakePhrases == ["computer", "hey computer"])
  #expect(configuration.submitPhrases == ["do it"])
  #expect(configuration.cancelPhrases == ["never mind"])
  #expect(configuration.silenceSeconds == 6.5)
  #expect(configuration.silenceThresholdDB == -38)
  #expect(configuration.maximumRecordingSeconds == 120)
  #expect(configuration.applicationCommands[.ghostty]?.newChat == ["make a chat"])
  #expect(configuration.applicationCommands[.ghostty]?.next == CommandPhrases.ghosttyDefaults.next)
}

@Test func rejectsPhraseCollisionAcrossActions() throws {
  let data = Data(
    """
    wake = ["ghostee"]
    submit = ["ghost it"]
    cancel = ["ghost it"]
    """.utf8
  )

  #expect(throws: ConfigurationError.self) {
    try Configuration.decodeTOML(data)
  }
}

@Test func rejectsCollisionWithGlobalApplicationFocusPhrase() {
  let data = Data(
    """
    [applications.ghostty.commands]
    new_chat = ["focus chat"]

    [applications.chatgpt.commands]
    focus = ["focus chat"]
    """.utf8
  )

  #expect(throws: ConfigurationError.self) {
    try Configuration.decodeTOML(data)
  }
}

@Test func customCommandAliasParsesAfterWakePhrase() throws {
  let configuration = try Configuration.decodeTOML(
    Data(
      """
      wake = ["computer"]

      [applications.ghostty.commands]
      new_chat = ["make a chat"]
      """.utf8
    )
  )

  #expect(
    ApplicationCommand.parse(
      "Computer, make a chat",
      wakePhrases: configuration.wakePhrases,
      mappings: configuration.commandMappings(for: .ghostty)
    ) == .newChat
  )
}

@Test func parsesGhosttyContextCommandsAfterWakePhrase() throws {
  let configuration = try Configuration.decodeTOML(Data())
  let mappings = configuration.commandMappings(for: .ghostty)

  #expect(
    ApplicationCommand.parse(
      "Computer, clear context",
      wakePhrases: ["computer"],
      mappings: mappings
    ) == .clearContext
  )
  #expect(
    ApplicationCommand.parse(
      "Computer, compact context",
      wakePhrases: ["computer"],
      mappings: mappings
    ) == .compactContext
  )
  #expect(
    ApplicationCommand.parse(
      "Computer, clear context",
      wakePhrases: ["computer"],
      mappings: configuration.commandMappings(for: .chrome)
    ) == nil
  )
}

@Test func cleansConfiguredWakeAndSubmitAliases() {
  #expect(
    PhraseMatcher.cleanFinalTranscript(
      "Hey computer write the test do it",
      wakePhrases: ["computer", "hey computer"],
      submitPhrases: ["do it", "ship it"]
    ) == "write the test"
  )
}

@Test func preservesPunctuationBeforeConfiguredSubmitPhrase() {
  #expect(
    PhraseMatcher.cleanFinalTranscript(
      "Here is a short prompt. Send it.",
      wakePhrases: ["pewter"],
      submitPhrases: ["send it", "sent it"]
    ) == "Here is a short prompt."
  )
}

@Test func matchesConfiguredControlPhraseNearTranscriptTail() {
  let transcript = KeywordTranscript(
    text: "write this send it accidental trailing",
    segments: [
      .init(text: "write", timestamp: 0, duration: 0.4),
      .init(text: "this", timestamp: 0.4, duration: 0.4),
      .init(text: "send", timestamp: 0.8, duration: 0.4),
      .init(text: "it", timestamp: 1.2, duration: 0.3),
      .init(text: "accidental", timestamp: 1.5, duration: 0.5),
      .init(text: "trailing", timestamp: 2.0, duration: 0.5),
    ]
  )

  let match = PhraseMatcher.trailingMatch(
    any: ["ship it", "send it"],
    in: transcript,
    maximumTrailingWords: 3
  )

  #expect(match?.phrase == "send it")
  #expect(match?.startTime == 0.8)
  #expect(match?.endTime == 1.5)
  #expect(match?.transcriptEndTime == 2.5)
  #expect(match.map { $0.transcriptEndTime - $0.endTime } == 1.0)
}

@Test func ignoresConfiguredControlPhraseOutsideTrailingWindow() {
  let transcript = KeywordTranscript(
    text: "send it as ordinary dictated content here",
    segments: [
      .init(text: "send", timestamp: 0, duration: 0.3),
      .init(text: "it", timestamp: 0.3, duration: 0.2),
      .init(text: "as", timestamp: 0.5, duration: 0.2),
      .init(text: "ordinary", timestamp: 0.7, duration: 0.4),
      .init(text: "dictated", timestamp: 1.1, duration: 0.4),
      .init(text: "content", timestamp: 1.5, duration: 0.3),
      .init(text: "here", timestamp: 1.8, duration: 0.3),
    ]
  )

  #expect(
    PhraseMatcher.trailingMatch(
      any: ["send it"],
      in: transcript,
      maximumTrailingWords: 3
    ) == nil
  )
}

@Test func calculatesRecordingCutoffFramesFromTranscriptTail() {
  #expect(
    RecordingCutoff.frameCount(
      secondsToRemoveFromEnd: 1.25,
      sampleRate: 16_000,
      availableFrames: 40_000
    ) == 20_000
  )
  #expect(
    RecordingCutoff.frameCount(
      secondsToRemoveFromEnd: -1,
      sampleRate: 16_000,
      availableFrames: 40_000
    ) == 40_000
  )
  #expect(
    RecordingCutoff.frameCount(
      secondsToRemoveFromEnd: 10,
      sampleRate: 16_000,
      availableFrames: 40_000
    ) == 0
  )
}

@Test func trimsRecordedAudioAtSubmitTimestamp() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let sourceURL = directory.appendingPathComponent("prompt.wav")
  let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
  buffer.frameLength = 48_000
  memset(buffer.floatChannelData![0], 0, Int(buffer.frameLength) * MemoryLayout<Float>.size)
  do {
    let file = try AVAudioFile(forWriting: sourceURL, settings: format.settings)
    try file.write(from: buffer)
  }

  let trimmedURL = try RecordingTrimmer.trim(
    sourceURL,
    secondsToRemoveFromEnd: 0.5
  )

  let trimmed = try AVAudioFile(forReading: trimmedURL)
  #expect(trimmed.length == 24_000)
}

@Test func reconcilesRevisedPartialTranscriptFromCommonPrefix() {
  var preview = TranscriptPreview()

  #expect(
    preview.replace(with: "open the red tab")
      == PreviewEdit(deleteCount: 0, insertion: "open the red tab")
  )
  #expect(
    preview.replace(with: "open the read tab")
      == PreviewEdit(deleteCount: 5, insertion: "ad tab")
  )
  #expect(preview.text == "open the read tab")
}

@Test func replacesLivePreviewWithFinalTranscript() {
  var preview = TranscriptPreview()
  _ = preview.replace(with: "draft trans script")

  let edit = preview.replace(with: "draft transcript")

  #expect(edit == PreviewEdit(deleteCount: 7, insertion: "cript"))
  #expect(preview.text == "draft transcript")
}

@Test func clearsEntireLivePreviewWhenRecordingIsCancelled() {
  var preview = TranscriptPreview()
  _ = preview.replace(with: "do not submit this")

  let edit = preview.replace(with: "")

  #expect(edit == PreviewEdit(deleteCount: 18, insertion: ""))
  #expect(preview.text.isEmpty)
}

@Test func waitsLongerBeforeSubmittingLargerPastes() {
  #expect(SubmissionTiming.returnDelay(for: String(repeating: "a", count: 50)) == 0.75)
  #expect(SubmissionTiming.returnDelay(for: String(repeating: "a", count: 300)) == 2.0)
  #expect(SubmissionTiming.returnDelay(for: String(repeating: "a", count: 1_000)) == 3.0)
}

@Test func reloadsChangedFileAndKeepsLastGoodConfigurationAfterAnError() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let fileURL = directory.appendingPathComponent("config.toml")
  try Data("wake = [\"ghostee\"]\n".utf8).write(to: fileURL)

  let store = try ConfigurationStore(fileURL: fileURL)
  var reloaded: Configuration?
  var reloadError: String?
  store.onConfigurationChanged = { reloaded = $0 }
  store.onError = { reloadError = $0 }

  try Data("wake = [\"computer\"]\n".utf8).write(to: fileURL)
  store.reloadIfChanged()
  #expect(reloaded?.wakePhrases == ["computer"])
  #expect(store.configuration.wakePhrases == ["computer"])

  try Data("wake = [\n".utf8).write(to: fileURL)
  store.reloadIfChanged()
  #expect(reloadError != nil)
  #expect(store.configuration.wakePhrases == ["computer"])
}
