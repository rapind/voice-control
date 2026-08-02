import AppKit
import Foundation

final class VoiceController {
  var onStateChanged: ((VoicePhase) -> Void)?
  var onConfigurationChanged: ((Configuration) -> Void)?

  private var configuration: Configuration
  private var pendingConfiguration: Configuration?
  private let audio = AudioCapture()
  private let keywords: KeywordListener
  private let applicationController = ApplicationController()
  private let transcriber = ParakeetTranscriber()
  private var machine = VoiceStateMachine()
  private var modelReady = false
  private var voiceReady = false
  private var targetPID: pid_t?
  private var lastSpeechAt = Date()
  private var recordingStartedAt = Date()
  private var ignoreSilenceUntil = Date()
  private var heardPromptSpeech = false
  private var silenceTimer: Timer?
  private var lastKeywordTranscript = ""

  init(configuration: Configuration) {
    self.configuration = configuration
    self.keywords = KeywordListener(contextualStrings: configuration.contextualPhrases)

    audio.onBuffer = { [weak self] buffer in
      self?.keywords.append(buffer)
    }
    audio.onLevel = { [weak self] db in
      guard db >= (self?.configuration.silenceThresholdDB ?? -42) else { return }
      DispatchQueue.main.async {
        guard let self, self.machine.phase == .recording, Date() >= self.ignoreSilenceUntil else {
          return
        }
        self.heardPromptSpeech = true
        self.lastSpeechAt = Date()
      }
    }
    keywords.onTranscript = { [weak self] transcript in
      self?.handleKeywordTranscript(transcript)
    }
    keywords.onError = { [weak self] message in
      guard let self, self.machine.phase == .waitingForWake else { return }
      self.fail("Wake phrase listener failed: \(message)")
    }
  }

  func start() {
    printConfiguration()
    _ = applicationController.requestAccessibilityPermission()
    requestVoicePermissions()

    Task { @MainActor in
      do {
        print("Loading Parakeet from the existing FluidAudio cache")
        try await transcriber.prepare()
        print("Parakeet ready")
        modelReady = true
        becomeReadyIfPossible()
      } catch {
        fail("Could not load Parakeet. \(error.localizedDescription)", recover: false)
      }
    }
  }

  func stop() {
    silenceTimer?.invalidate()
    silenceTimer = nil
    keywords.stop()
    audio.stop()
  }

  func updateConfiguration(_ configuration: Configuration) {
    if configuration == self.configuration {
      onConfigurationChanged?(configuration)
      return
    }
    pendingConfiguration = configuration
    if machine.phase == .waitingForWake {
      _ = applyPendingConfiguration()
    }
  }

  private func requestVoicePermissions() {
    var microphoneGranted: Bool?
    var speechGranted: Bool?

    func finishIfReady() {
      guard let microphoneGranted, let speechGranted else { return }
      guard microphoneGranted else {
        fail("Microphone permission was denied", recover: false)
        return
      }
      guard speechGranted else {
        fail("Speech Recognition permission was denied", recover: false)
        return
      }
      do {
        try audio.start()
        voiceReady = true
        becomeReadyIfPossible()
      } catch {
        fail("Microphone failed to start: \(error.localizedDescription)", recover: false)
      }
    }

    AudioCapture.requestPermission { granted in
      microphoneGranted = granted
      finishIfReady()
    }
    KeywordListener.requestPermission { granted in
      speechGranted = granted
      finishIfReady()
    }
  }

  private func becomeReadyIfPossible() {
    guard machine.phase == .starting, modelReady, voiceReady else { return }
    dispatch(.ready)
  }

  private func dispatch(_ event: VoiceEvent) {
    let effects = machine.handle(event)
    reportState()
    for effect in effects {
      perform(effect)
    }
  }

  private func perform(_ effect: VoiceEffect) {
    switch effect {
    case .startWakeListening:
      guard applyPendingConfiguration() else { return }
      lastKeywordTranscript = ""
      do {
        try keywords.start()
      } catch {
        fail(error.localizedDescription)
      }

    case .beginPromptRecording:
      targetPID = applicationController.captureTargetPID(for: configuration.target)
      heardPromptSpeech = false
      recordingStartedAt = Date()
      ignoreSilenceUntil = Date().addingTimeInterval(0.6)
      lastSpeechAt = ignoreSilenceUntil
      do {
        try audio.beginRecording()
        NSSound(named: "Tink")?.play()
        startSilenceTimer()
        applicationController.focus(configuration.target, targetPID: targetPID) {
          [weak self] result in
          DispatchQueue.main.async {
            guard let self, self.machine.phase == .recording else { return }
            if case .failure(let error) = result {
              self.fail(error.localizedDescription)
            }
          }
        }
      } catch {
        fail("Could not begin recording: \(error.localizedDescription)")
      }

    case .stopAndTranscribe:
      silenceTimer?.invalidate()
      silenceTimer = nil
      keywords.stop()
      NSSound(named: "Pop")?.play()
      guard let fileURL = audio.finishRecording() else {
        fail("No prompt recording was available")
        return
      }
      transcribe(fileURL)

    case .cancelPromptRecording:
      silenceTimer?.invalidate()
      silenceTimer = nil
      keywords.stop()
      discardPromptRecording()
      NSSound(named: "Pop")?.play()

    case .inject(let text):
      if let command = ApplicationCommand.parse(
        text,
        wakePhrases: configuration.wakePhrases,
        commands: configuration.activeCommands
      ) {
        execute(command)
      } else {
        applicationController.inject(
          text, into: configuration.target, targetPID: targetPID
        ) { [weak self] result in
          self?.completeApplicationOperation(result)
        }
      }

    case .executeCommand(let command):
      silenceTimer?.invalidate()
      silenceTimer = nil
      keywords.stop()
      discardPromptRecording()
      NSSound(named: "Pop")?.play()
      execute(command)

    case .reportError(let message):
      NSSound.beep()
      print("ERROR: \(message)")
    }
  }

  private func handleKeywordTranscript(_ transcript: String) {
    let normalized = PhraseMatcher.normalize(transcript)
    guard normalized != lastKeywordTranscript else { return }
    lastKeywordTranscript = normalized

    switch machine.phase {
    case .waitingForWake:
      if PhraseMatcher.contains(any: configuration.wakePhrases, in: transcript) {
        print("Wake phrase detected")
        dispatch(.wakeDetected)
      }
    case .recording:
      if PhraseMatcher.contains(any: configuration.cancelPhrases, in: transcript) {
        print("Cancel phrase detected")
        dispatch(.cancelDetected)
      } else if PhraseMatcher.contains(any: configuration.submitPhrases, in: transcript) {
        print("Submit phrase detected")
        dispatch(.submitDetected)
      } else if let command = ApplicationCommand.parse(
        transcript,
        wakePhrases: configuration.wakePhrases,
        commands: configuration.activeCommands
      ) {
        print("\(configuration.target.displayName) command detected: \(command)")
        dispatch(.commandDetected(command))
      }
    default:
      break
    }
  }

  private func startSilenceTimer() {
    silenceTimer?.invalidate()
    let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] timer in
      guard let self else {
        timer.invalidate()
        return
      }
      guard self.machine.phase == .recording else {
        timer.invalidate()
        return
      }
      let now = Date()
      if now.timeIntervalSince(self.recordingStartedAt)
        >= self.configuration.maximumRecordingSeconds
      {
        self.dispatch(.maximumDurationExpired)
        return
      }
      guard self.heardPromptSpeech, now >= self.ignoreSilenceUntil else { return }
      if now.timeIntervalSince(self.lastSpeechAt) >= self.configuration.silenceSeconds {
        print("Silence fallback reached")
        self.dispatch(.silenceExpired)
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    silenceTimer = timer
  }

  private func transcribe(_ fileURL: URL) {
    Task { @MainActor in
      defer { try? FileManager.default.removeItem(at: fileURL) }
      do {
        let transcript = try await transcriber.transcribe(fileURL: fileURL)
        let cleaned = PhraseMatcher.cleanFinalTranscript(
          transcript,
          wakePhrases: configuration.wakePhrases,
          submitPhrases: configuration.submitPhrases
        )
        guard !cleaned.isEmpty else {
          fail("Parakeet returned an empty prompt")
          return
        }
        print("Transcript: \(cleaned)")
        dispatch(.transcriptionSucceeded(cleaned))
      } catch {
        fail("Transcription failed: \(error.localizedDescription)")
      }
    }
  }

  private func execute(_ command: ApplicationCommand) {
    applicationController.execute(
      command, for: configuration.target, targetPID: targetPID
    ) { [weak self] result in
      self?.completeApplicationOperation(result)
    }
  }

  private func applyPendingConfiguration() -> Bool {
    guard let updated = pendingConfiguration else { return true }
    do {
      try keywords.updateContextualStrings(updated.contextualPhrases)
      configuration = updated
      pendingConfiguration = nil
      printConfiguration()
      onConfigurationChanged?(updated)
      return true
    } catch {
      pendingConfiguration = nil
      fail("Could not apply the reloaded configuration: \(error.localizedDescription)")
      return false
    }
  }

  private func discardPromptRecording() {
    if let recordingURL = audio.finishRecording() {
      try? FileManager.default.removeItem(at: recordingURL)
    }
  }

  private func completeApplicationOperation(_ result: Result<Void, Error>) {
    DispatchQueue.main.async {
      switch result {
      case .success:
        self.dispatch(.injectionCompleted)
      case .failure(let error):
        self.fail(error.localizedDescription)
      }
    }
  }

  private func fail(_ message: String, recover: Bool = true) {
    silenceTimer?.invalidate()
    silenceTimer = nil
    keywords.stop()
    _ = audio.finishRecording()
    dispatch(.failed(message))
    guard recover else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
      self?.dispatch(.recover)
    }
  }

  private func reportState() {
    print("STATE: \(machine.phase.description)")
    onStateChanged?(machine.phase)
  }

  private func printConfiguration() {
    print("Voice Control Prototype")
    print("  target: \(configuration.target.displayName)")
    print("  wake phrases: \(configuration.wakePhrases.joined(separator: ", "))")
    print("  submit phrases: \(configuration.submitPhrases.joined(separator: ", "))")
    print("  cancel phrases: \(configuration.cancelPhrases.joined(separator: ", "))")
    print(
      "  silence fallback: \(configuration.silenceSeconds)s at \(configuration.silenceThresholdDB)dBFS"
    )
    print("  transcription: local Parakeet v3 via FluidAudio")
  }
}
