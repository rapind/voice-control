import Foundation
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
  #expect(ApplicationCommand.sleepMacBook.isDirectCommand)
  #expect(ApplicationCommand.sleepMacBook.isGlobalDirectCommand)
  #expect(ApplicationCommand.clearContext.isDirectCommand)
  #expect(ApplicationCommand.compactContext.isDirectCommand)
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

@Test func promptCaptureWaitsForTheWakeConfirmationSoundToFinish() {
  #expect(WakeConfirmation.captureDelay(soundDuration: nil) == 0)
  #expect(WakeConfirmation.captureDelay(soundDuration: 0) == 0)
  #expect(abs(WakeConfirmation.captureDelay(soundDuration: 0.564) - 0.614) < 0.000_001)
}

@Test func maximumRecordingDurationExpiresOnlyAtTheLimit() {
  let now = Date(timeIntervalSinceReferenceDate: 200)

  #expect(
    !MaximumRecordingDuration.hasExpired(
      now: now,
      recordingStartedAt: now.addingTimeInterval(-89),
      maximumRecordingSeconds: 90
    )
  )
  #expect(
    MaximumRecordingDuration.hasExpired(
      now: now,
      recordingStartedAt: now.addingTimeInterval(-90),
      maximumRecordingSeconds: 90
    )
  )
}
