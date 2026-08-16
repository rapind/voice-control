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

@Test func ghosttyContextCommandsSubmitCodexSlashCommands() {
  let controller = ApplicationController()

  #expect(controller.slashCommandText(for: .clearContext, target: .ghostty) == "/clear")
  #expect(controller.slashCommandText(for: .compactContext, target: .ghostty) == "/compact")
  #expect(controller.slashCommandText(for: .clearContext, target: .chrome) == nil)
}

@Test func ghosttySessionControlsInterruptAndStartOMP() throws {
  let controller = ApplicationController()
  let controlC = try #require(
    controller.keyStroke(for: .interruptSession, target: .ghostty)
  )

  #expect(controlC.keyCode == 8)
  #expect(controlC.flags == .maskControl)
  #expect(controller.textToSubmit(for: .startSession, target: .ghostty) == "omp")
  #expect(controller.keyStroke(for: .interruptSession, target: .chrome) == nil)
  #expect(controller.textToSubmit(for: .startSession, target: .chrome) == nil)
}
