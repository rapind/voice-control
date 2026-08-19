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
  #expect(ScrollCommand.pixelsToEnd == 3_000)
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
