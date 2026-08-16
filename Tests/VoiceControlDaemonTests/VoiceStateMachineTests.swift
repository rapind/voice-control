import Testing

@testable import VoiceControlDaemon

@Test func numberedFocusCommandExecutesFromIdle() {
  var machine = VoiceStateMachine()
  _ = machine.handle(.ready)

  let effects = machine.handle(.commandDetected(.focusItem(8)))

  #expect(machine.phase == .injecting)
  #expect(effects.count == 1)
  guard case .executeCommand(.focusItem(8)) = effects[0] else {
    Issue.record("Expected direct focus command execution")
    return
  }
}

@Test func directFocusCommandsAreLimitedToFirstEightItems() {
  #expect(ApplicationCommand.focusItem(1).isDirectFocusCommand)
  #expect(ApplicationCommand.focusItem(8).isDirectFocusCommand)
  #expect(!ApplicationCommand.focusItem(9).isDirectFocusCommand)
  #expect(!ApplicationCommand.newChat.isDirectFocusCommand)
}
