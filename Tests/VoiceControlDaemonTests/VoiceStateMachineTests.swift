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

@Test func directCommandsExecuteFromIdle() {
  #expect(ApplicationCommand.focusItem(1).isDirectCommand)
  #expect(ApplicationCommand.focusItem(8).isDirectCommand)
  #expect(!ApplicationCommand.focusItem(9).isDirectCommand)
  #expect(ApplicationCommand.scrollUp.isDirectCommand)
  #expect(ApplicationCommand.scrollDown.isDirectCommand)
  #expect(ApplicationCommand.scrollEnd.isDirectCommand)
  #expect(ApplicationCommand.playMusic.isDirectCommand)
  #expect(ApplicationCommand.pauseMusic.isDirectCommand)
  #expect(ApplicationCommand.nextSong.isDirectCommand)
  #expect(ApplicationCommand.previousSong.isDirectCommand)
  #expect(ApplicationCommand.launchMusic.isDirectCommand)
  #expect(!ApplicationCommand.newChat.isDirectCommand)
}

@Test func wakeListenerRecoversOnlyWhenIdleAudioStalls() {
  #expect(
    WakeListenerHealth.shouldRecover(
      phase: .waitingForWake,
      audioIsRunning: false,
      isReceivingAudio: true,
      restartIsScheduled: false))
  #expect(
    WakeListenerHealth.shouldRecover(
      phase: .waitingForWake,
      audioIsRunning: true,
      isReceivingAudio: false,
      restartIsScheduled: false))
  #expect(
    !WakeListenerHealth.shouldRecover(
      phase: .waitingForWake,
      audioIsRunning: true,
      isReceivingAudio: true,
      restartIsScheduled: false))
  #expect(
    !WakeListenerHealth.shouldRecover(
      phase: .recording,
      audioIsRunning: false,
      isReceivingAudio: true,
      restartIsScheduled: false))
  #expect(
    !WakeListenerHealth.shouldRecover(
      phase: .waitingForWake,
      audioIsRunning: false,
      isReceivingAudio: false,
      restartIsScheduled: true))
}
