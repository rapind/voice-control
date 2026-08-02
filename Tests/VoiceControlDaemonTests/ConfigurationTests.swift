import Foundation
import Testing

@testable import VoiceControlDaemon

@Test func decodesChatGPTAsActiveTarget() throws {
  let configuration = try Configuration.decodeTOML(
    Data(
      """
      target = "chatgpt"
      """.utf8
    )
  )

  #expect(configuration.target == .chatGPT)
}

@Test func onlyActiveTargetCommandsAreParsed() throws {
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
      commands: configuration.activeCommands
    ) == .newChat
  )
  #expect(
    ApplicationCommand.parse(
      "open terminal chat",
      wakePhrases: configuration.wakePhrases,
      commands: configuration.activeCommands
    ) == nil
  )
  #expect(
    ApplicationCommand.parse(
      "focus 1",
      wakePhrases: configuration.wakePhrases,
      commands: configuration.activeCommands
    ) == .focusItem(1)
  )
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

@Test func speechContextOnlyIncludesTheActiveApplicationsCommands() throws {
  let configuration = try Configuration.decodeTOML(
    Data(
      """
      target = "chatgpt"

      [applications.ghostty.commands]
      focus = ["terminal only"]

      [applications.chatgpt.commands]
      focus = ["app only"]
      """.utf8
    )
  )

  #expect(configuration.contextualPhrases.contains("app only"))
  #expect(!configuration.contextualPhrases.contains("terminal only"))
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
  #expect(configuration.activeCommands.newChat == ["make a chat"])
  #expect(configuration.activeCommands.next == CommandPhrases.ghosttyDefaults.next)
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
      commands: configuration.activeCommands
    ) == .newChat
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
