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

@Test func chatGPTScrollUsesPageKeys() throws {
  let controller = ApplicationController()
  let pageUp = try #require(controller.keyStroke(for: .scrollUp, target: .chatGPT))
  let pageDown = try #require(controller.keyStroke(for: .scrollDown, target: .chatGPT))

  #expect(pageUp.keyCode == 116)
  #expect(pageUp.flags.isEmpty)
  #expect(pageDown.keyCode == 121)
  #expect(pageDown.flags.isEmpty)
  #expect(controller.keyStroke(for: .scrollUp, target: .ghostty) == nil)
  #expect(controller.keyStroke(for: .scrollDown, target: .chrome) == nil)
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
