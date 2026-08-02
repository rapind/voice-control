import Foundation
import Testing

@testable import VoiceControlDaemon

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

      [commands]
      new_tab = ["make a tab"]
      """.utf8
    )
  )

  #expect(configuration.wakePhrases == ["computer", "hey computer"])
  #expect(configuration.submitPhrases == ["do it"])
  #expect(configuration.cancelPhrases == ["never mind"])
  #expect(configuration.silenceSeconds == 6.5)
  #expect(configuration.silenceThresholdDB == -38)
  #expect(configuration.maximumRecordingSeconds == 120)
  #expect(configuration.commands.newTab == ["make a tab"])
  #expect(configuration.commands.nextTab == CommandPhrases.defaults.nextTab)
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

      [commands]
      new_tab = ["make a tab"]
      """.utf8
    )
  )

  #expect(
    GhosttyCommand.parse(
      "Computer, make a tab",
      wakePhrases: configuration.wakePhrases,
      commands: configuration.commands
    ) == .newTab
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
