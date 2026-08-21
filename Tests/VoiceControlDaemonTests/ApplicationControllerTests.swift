import ApplicationServices
import Testing

@testable import VoiceControlDaemon

@Test func ghosttyNumberedFocusUsesHerdrWorkspaceChord() throws {
  let keyStroke = try #require(
    ApplicationController().keyStroke(for: .focusItem(3), target: .ghostty)
  )

  #expect(keyStroke.keyCode == 20)
  #expect(keyStroke.flags == [.maskControl, .maskAlternate])
}

@Test func chromeNumberedFocusKeepsNativeTabChord() throws {
  let keyStroke = try #require(
    ApplicationController().keyStroke(for: .focusItem(3), target: .chrome)
  )

  #expect(keyStroke.keyCode == 20)
  #expect(keyStroke.flags == .maskCommand)
}

@Test func chatGPTScrollsFartherWithoutUsingPageKeys() {
  let controller = ApplicationController()

  #expect(ScrollCommand.pixelsPerStep(for: .chatGPT) == 670)
  #expect(ScrollCommand.pixelsPerStep(for: .ghostty) == 160)
  #expect(ScrollCommand.pixelsPerStep(for: .chrome) == 160)
  #expect(controller.keyStroke(for: .scrollUp, target: .chatGPT) == nil)
  #expect(controller.keyStroke(for: .scrollDown, target: .chatGPT) == nil)
  #expect(ScrollCommand.pixelsToEnd == 20_000)
}

@Test func chatGPTTabCommandsUseTheAppMenuShortcuts() throws {
  let controller = ApplicationController()
  let newTab = try #require(controller.keyStroke(for: .newChat, target: .chatGPT))
  let closeTab = try #require(controller.keyStroke(for: .closeTab, target: .chatGPT))
  let clearContext = try #require(
    controller.keyStroke(for: .clearContext, target: .chatGPT))

  #expect(newTab.keyCode == 45)
  #expect(newTab.flags == .maskCommand)
  #expect(closeTab.keyCode == 13)
  #expect(closeTab.flags == .maskCommand)
  #expect(clearContext == newTab)
  #expect(controller.slashCommandText(for: .clearContext, target: .chatGPT) == nil)
  #expect(controller.slashCommandText(for: .compactContext, target: .chatGPT) == nil)
  #expect(controller.keyStroke(for: .closeTab, target: .ghostty) == nil)
}

@Test func herdrWorkspaceCommandsCreateAndCloseTheFocusedWorkspace() throws {
  #expect(HerdrWorkspaceControl.createArguments == ["workspace", "create", "--focus"])

  let response = Data(
    """
    {"result":{"type":"workspace_list","workspaces":[
      {"focused":false,"workspace_id":"w0"},
      {"focused":true,"workspace_id":"w11"}
    ]}}
    """.utf8
  )

  #expect(try HerdrWorkspaceControl.focusedWorkspaceID(from: response) == "w11")
  #expect(
    HerdrWorkspaceControl.closeArguments(workspaceID: "w11") == ["workspace", "close", "w11"])
}

@Test func ghosttyContextCommandsSubmitCodexSlashCommands() {
  let controller = ApplicationController()

  #expect(controller.slashCommandText(for: .clearContext, target: .ghostty) == "/clear")
  #expect(controller.slashCommandText(for: .compactContext, target: .ghostty) == "/compact")
  #expect(controller.slashCommandText(for: .shareSession, target: .ghostty) == "/collab")
  #expect(controller.slashCommandText(for: .shareSession, target: .chrome) == nil)
  #expect(controller.slashCommandText(for: .stopSharing, target: .ghostty) == "/collab stop")
  #expect(controller.slashCommandText(for: .stopSharing, target: .chrome) == nil)
}

@Test func ghosttyStartSessionSubmitsOMP() {
  let controller = ApplicationController()

  #expect(controller.textToSubmit(for: .startSession, target: .ghostty) == "omp")
  #expect(controller.textToSubmit(for: .startSession, target: .chrome) == nil)
}

@Test func musicControlsUseSystemMediaEvents() throws {
  let controller = ApplicationController()

  #expect(controller.mediaKeyType(for: .playMusic) == 16)
  #expect(controller.mediaKeyType(for: .pauseMusic) == 16)
  #expect(controller.mediaKeyType(for: .nextSong) == 17)
  #expect(controller.mediaKeyType(for: .previousSong) == 18)
  #expect(controller.mediaKeyType(for: .scrollDown) == nil)
}

@Test func youtubeMusicUsesTheInstalledChromeAppBundle() {
  #expect(
    ApplicationController.youtubeMusicBundleIdentifier
      == "com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod"
  )
}

@Test func sleepMacBookUsesTheSystemSleepAppleEvent() {
  #expect(
    ApplicationController.sleepScriptSource
      == "tell application \"System Events\" to sleep"
  )
}
