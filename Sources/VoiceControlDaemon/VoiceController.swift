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
  private let transcriber: PromptTranscriber
  private let liveAudioRouter = LiveAudioBufferRouter()
  private var machine = VoiceStateMachine()
  private var modelReady = false
  private var voiceReady = false
  private var targetPID: pid_t?
  private var sessionTarget: ApplicationTarget?
  private var lastSpeechAt = Date()
  private var recordingStartedAt = Date()
  private var submitTailDuration: TimeInterval?
  private var ignoreSilenceUntil = Date()
  private var heardPromptSpeech = false
  private var silenceTimer: Timer?
  private var lastKeywordTranscript = ""
  private var preview = TranscriptPreview()
  private var pendingPreviewText = ""
  private var previewReady = false

  init(configuration: Configuration) {
    self.configuration = configuration
    self.transcriber = PromptTranscriber(contextualStrings: configuration.contextualPhrases)
    self.keywords = KeywordListener(contextualStrings: configuration.contextualPhrases)

    audio.onBuffer = { [weak self] buffer, startTime in
      self?.keywords.append(buffer, startingAt: startTime)
    }
    let liveAudioRouter = self.liveAudioRouter
    audio.onRecordingBuffer = { buffer in
      liveAudioRouter.appendCopy(of: buffer)
    }
    audio.onLevel = { [weak self] db in
      guard db >= (self?.configuration.silenceThresholdDB ?? -45) else { return }
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
        print("Loading \(transcriber.name)")
        try await transcriber.prepare()
        print("\(transcriber.name) ready")
        modelReady = true
        becomeReadyIfPossible()
      } catch {
        fail("Could not load \(transcriber.name). \(error.localizedDescription)", recover: false)
      }
    }
  }

  func stop() {
    silenceTimer?.invalidate()
    silenceTimer = nil
    keywords.stop()
    stopLiveTranscription()
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
      captureSessionTarget()
      recordingStartedAt = Date()
      ignoreSilenceUntil = Date().addingTimeInterval(0.6)
      lastSpeechAt = ignoreSilenceUntil
      submitTailDuration = nil
      preview = TranscriptPreview()
      pendingPreviewText = ""
      previewReady = targetPID != nil
      let liveInput = LiveAudioBufferSink()
      liveAudioRouter.route(to: liveInput)
      startLiveTranscription(input: liveInput)
      do {
        try audio.beginRecording()
        NSSound(named: "Tink")?.play()
        startSilenceTimer()
        applyPendingPreview()
      } catch {
        fail("Could not begin recording: \(error.localizedDescription)")
      }

    case .stopAndTranscribe:
      silenceTimer?.invalidate()
      silenceTimer = nil
      keywords.stop()
      NSSound(named: "Pop")?.play()
      liveAudioRouter.finish()
      let fileURL: URL?
      do {
        if let submitTailDuration {
          fileURL = try audio.finishRecording(removingTailOf: submitTailDuration)
        } else {
          fileURL = audio.finishRecording()
        }
      } catch {
        fail("Could not trim the submit command from the recording: \(error.localizedDescription)")
        return
      }
      self.submitTailDuration = nil
      guard let fileURL else {
        fail("No prompt recording was available")
        return
      }
      transcribe(fileURL)

    case .cancelPromptRecording:
      silenceTimer?.invalidate()
      silenceTimer = nil
      keywords.stop()
      stopLiveTranscription()
      discardPromptRecording()
      if case .failure(let error) = clearLivePreview() {
        print("ERROR: Could not clear cancelled live transcription: \(error.localizedDescription)")
      }
      NSSound(named: "Pop")?.play()

    case .inject(let text):
      if let command = ApplicationCommand.parse(
        text,
        wakePhrases: configuration.wakePhrases,
        mappings: configuration.commandMappings(for: sessionTarget)
      ) {
        if case .failure(let error) = clearLivePreview() {
          fail(error.localizedDescription)
          return
        }
        execute(command)
      } else {
        let edit = preview.replace(with: text)
        applicationController.submitPreview(
          edit,
          finalText: text,
          targetPID: targetPID
        ) { [weak self] result in
          self?.completeApplicationOperation(result)
        }
      }

    case .executeCommand(let command):
      silenceTimer?.invalidate()
      silenceTimer = nil
      keywords.stop()
      stopLiveTranscription()
      discardPromptRecording()
      NSSound(named: "Pop")?.play()
      if case .failure(let error) = clearLivePreview() {
        fail(error.localizedDescription)
        return
      }
      execute(command)

    case .reportError(let message):
      NSSound.beep()
      print("ERROR: \(message)")
    }
  }

  private func handleKeywordTranscript(_ transcript: KeywordTranscript) {
    let normalized = PhraseMatcher.normalize(transcript.text)
    guard normalized != lastKeywordTranscript else { return }
    lastKeywordTranscript = normalized

    switch machine.phase {
    case .waitingForWake:
      if let command = ApplicationCommand.parse(
        transcript.text,
        wakePhrases: configuration.wakePhrases,
        mappings: configuration.commandMappings(for: nil)
      ),
        command.isDirectFocusCommand
      {
        captureSessionTarget()
        if let sessionTarget,
          let targetCommand = ApplicationCommand.parse(
            transcript.text,
            wakePhrases: configuration.wakePhrases,
            mappings: configuration.commandMappings(for: sessionTarget)
          ),
          targetCommand.isDirectFocusCommand
        {
          print("\(sessionTarget.displayName) direct focus command detected: \(targetCommand)")
          dispatch(.commandDetected(targetCommand))
          return
        }
      }
      if PhraseMatcher.contains(any: configuration.wakePhrases, in: transcript.text) {
        print("Wake phrase detected")
        dispatch(.wakeDetected)
      }
    case .recording:
      if PhraseMatcher.trailingMatch(
        any: configuration.cancelPhrases,
        in: transcript,
        maximumTrailingWords: 6
      ) != nil {
        print("Cancel phrase detected")
        dispatch(.cancelDetected)
      } else if let match = PhraseMatcher.trailingMatch(
        any: configuration.submitPhrases,
        in: transcript,
        maximumTrailingWords: 6
      ) {
        submitTailDuration = max(0, match.transcriptEndTime - match.endTime)
        print("Submit phrase detected")
        dispatch(.submitDetected)
      } else if let command = ApplicationCommand.parse(
        transcript.text,
        wakePhrases: configuration.wakePhrases,
        mappings: configuration.commandMappings(for: sessionTarget)
      ) {
        if let commandTarget = command.target(frontmost: sessionTarget) {
          print("\(commandTarget.displayName) command detected: \(command)")
        }
        dispatch(.commandDetected(command))
      }
    default:
      break
    }
  }

  private func startLiveTranscription(input: LiveAudioBufferSink) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        try await transcriber.startLiveTranscription(
          input: input,
          onUpdate: { [weak self] text in
            self?.handleLiveTranscript(text)
          },
          onError: { [weak self] message in
            guard let self, self.machine.phase == .recording else { return }
            self.fail("Live \(self.transcriber.name) failed: \(message)")
          }
        )
      } catch {
        guard machine.phase == .recording else { return }
        fail("Could not start live \(transcriber.name): \(error.localizedDescription)")
      }
    }
  }

  private func stopLiveTranscription() {
    liveAudioRouter.finish()
    Task {
      await transcriber.stopLiveTranscription()
    }
  }

  private func handleLiveTranscript(_ text: String) {
    guard machine.phase == .recording else { return }
    pendingPreviewText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    applyPendingPreview()
  }

  private func applyPendingPreview() {
    guard machine.phase == .recording, previewReady else { return }
    var nextPreview = preview
    let edit = nextPreview.replace(with: pendingPreviewText)
    guard edit.deleteCount > 0 || !edit.insertion.isEmpty else { return }
    switch applicationController.applyPreviewEdit(
      edit,
      targetPID: targetPID
    ) {
    case .success:
      preview = nextPreview
    case .failure(let error):
      fail(error.localizedDescription)
    }
  }

  private func clearLivePreview() -> Result<Void, Error> {
    pendingPreviewText = ""
    guard previewReady else {
      preview = TranscriptPreview()
      return .success(())
    }
    var emptyPreview = preview
    let edit = emptyPreview.replace(with: "")
    guard edit.deleteCount > 0 || !edit.insertion.isEmpty else { return .success(()) }
    let result = applicationController.applyPreviewEdit(
      edit,
      targetPID: targetPID
    )
    if case .success = result {
      preview = emptyPreview
    }
    return result
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
          fail("\(transcriber.name) returned an empty prompt")
          return
        }
        print("Transcript: \(cleaned)")
        dispatch(.transcriptionSucceeded(cleaned))
      } catch {
        fail("Transcription failed: \(error.localizedDescription)")
      }
    }
  }

  private func captureSessionTarget() {
    let capturedApplication = applicationController.captureFrontmostApplication()
    targetPID = capturedApplication?.processIdentifier
    sessionTarget = capturedApplication?.target
  }

  private func execute(_ command: ApplicationCommand) {
    guard let commandTarget = command.target(frontmost: sessionTarget) else {
      print("Command ignored because the captured application is unsupported: \(command)")
      completeApplicationOperation(.success(()))
      return
    }
    let commandTargetPID =
      command.focusTarget == nil
      ? targetPID : applicationController.captureTargetPID(for: commandTarget)
    applicationController.execute(
      command, for: commandTarget, targetPID: commandTargetPID
    ) { [weak self] result in
      self?.completeApplicationOperation(result)
    }
  }

  private func applyPendingConfiguration() -> Bool {
    guard let updated = pendingConfiguration else { return true }
    do {
      try keywords.updateContextualStrings(updated.contextualPhrases)
      configuration = updated
      Task { [transcriber] in
        await transcriber.updateContextualStrings(updated.contextualPhrases)
      }
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
    stopLiveTranscription()
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
    print("  routing: frontmost application")
    print("  wake phrases: \(configuration.wakePhrases.joined(separator: ", "))")
    print("  submit phrases: \(configuration.submitPhrases.joined(separator: ", "))")
    print("  cancel phrases: \(configuration.cancelPhrases.joined(separator: ", "))")
    print(
      "  silence fallback: \(configuration.silenceSeconds)s at \(configuration.silenceThresholdDB)dBFS"
    )
    print("  transcription: \(transcriber.name)")
  }
}
