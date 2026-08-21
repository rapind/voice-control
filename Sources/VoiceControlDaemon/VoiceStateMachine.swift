import Foundation

enum VoicePhase: Equatable, CustomStringConvertible {
  case starting
  case waitingForWake
  case recording
  case transcribing
  case injecting
  case failed(String)

  var description: String {
    switch self {
    case .starting: return "starting"
    case .waitingForWake: return "waiting for wake phrase"
    case .recording: return "recording prompt"
    case .transcribing: return "transcribing"
    case .injecting: return "sending to target application"
    case .failed(let message): return "error: \(message)"
    }
  }
}

enum VoiceEvent {
  case ready
  case wakeDetected
  case submitDetected
  case cancelDetected
  case silenceExpired
  case maximumDurationExpired
  case commandDetected(ApplicationCommand)
  case transcriptionSucceeded(String)
  case failed(String)
  case injectionCompleted
  case recover
}

enum VoiceEffect {
  case startWakeListening
  case beginPromptRecording
  case stopAndTranscribe
  case cancelPromptRecording
  case executeCommand(ApplicationCommand)
  case inject(String)
  case reportError(String)
}

struct VoiceStateMachine {
  private(set) var phase: VoicePhase = .starting

  mutating func handle(_ event: VoiceEvent) -> [VoiceEffect] {
    switch (phase, event) {
    case (.starting, .ready):
      phase = .waitingForWake
      return [.startWakeListening]

    case (.waitingForWake, .wakeDetected):
      phase = .recording
      return [.beginPromptRecording]

    case (.waitingForWake, .commandDetected(let command)):
      phase = .injecting
      return [.executeCommand(command)]

    case (.recording, .submitDetected),
      (.recording, .silenceExpired),
      (.recording, .maximumDurationExpired):
      phase = .transcribing
      return [.stopAndTranscribe]

    case (.recording, .cancelDetected):
      phase = .waitingForWake
      return [.cancelPromptRecording, .startWakeListening]

    case (.recording, .commandDetected(let command)):
      phase = .injecting
      return [.executeCommand(command)]

    case (.transcribing, .transcriptionSucceeded(let text)):
      phase = .injecting
      return [.inject(text)]

    case (.injecting, .injectionCompleted):
      phase = .waitingForWake
      return [.startWakeListening]

    case (_, .failed(let message)):
      phase = .failed(message)
      return [.reportError(message)]

    case (.failed, .recover):
      phase = .waitingForWake
      return [.startWakeListening]

    default:
      return []
    }
  }
}

enum AutomaticSubmissionTrigger: Equatable {
  case silence
  case maximumDuration
}

enum WakeConfirmation {
  private static let completionMargin: TimeInterval = 0.05

  static func captureDelay(soundDuration: TimeInterval?) -> TimeInterval {
    guard let soundDuration, soundDuration.isFinite, soundDuration > 0 else { return 0 }
    return min(soundDuration + completionMargin, 1)
  }
}

enum AutomaticSubmission {
  static func trigger(
    enabled: Bool,
    now: Date,
    recordingStartedAt: Date,
    lastSpeechAt: Date,
    ignoreSilenceUntil: Date,
    heardPromptSpeech: Bool,
    silenceSeconds: TimeInterval,
    maximumRecordingSeconds: TimeInterval
  ) -> AutomaticSubmissionTrigger? {
    guard enabled else { return nil }
    if now.timeIntervalSince(recordingStartedAt) >= maximumRecordingSeconds {
      return .maximumDuration
    }
    guard heardPromptSpeech, now >= ignoreSilenceUntil else { return nil }
    return now.timeIntervalSince(lastSpeechAt) >= silenceSeconds ? .silence : nil
  }
}
