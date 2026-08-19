import AVFoundation
import Foundation

final class AudioCapture {
  var onBuffer: ((AVAudioPCMBuffer, TimeInterval) -> Void)?
  var onRecordingBuffer: ((AVAudioPCMBuffer) -> Void)?
  var onLevel: ((Float) -> Void)?
  var onConfigurationChange: (() -> Void)?

  private let engine = AVAudioEngine()
  private let lock = NSLock()
  private var recordingFile: AVAudioFile?
  private var recordingURL: URL?
  private var totalCapturedTime: TimeInterval = 0
  private var tapInstalled = false
  private var tapFormat: AVAudioFormat?
  private var lastBufferReceivedAt: Date?
  private var configurationChangeObserver: NSObjectProtocol?

  init() {
    configurationChangeObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: .main
    ) { [weak self] _ in
      self?.onConfigurationChange?()
    }
  }

  deinit {
    if let configurationChangeObserver {
      NotificationCenter.default.removeObserver(configurationChangeObserver)
    }
  }

  var isRunning: Bool { engine.isRunning }

  /// True when audio buffers have arrived recently. A running engine that is
  /// not delivering buffers means the tap failed to install, for example when
  /// the input device changed while the engine was reconfiguring.
  var isReceivingAudio: Bool {
    lock.lock()
    defer { lock.unlock() }
    guard let lastBufferReceivedAt else { return false }
    return Date().timeIntervalSince(lastBufferReceivedAt) < 3
  }

  static func requestPermission(_ completion: @escaping (Bool) -> Void) {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      completion(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        DispatchQueue.main.async { completion(granted) }
      }
    default:
      completion(false)
    }
  }

  func start() throws {
    guard !engine.isRunning else { return }
    let input = engine.inputNode
    let hardwareFormat = input.inputFormat(forBus: 0)
    let format = input.outputFormat(forBus: 0)
    guard
      AudioFormatReadiness.canInstallTap(
        hardwareSampleRate: hardwareFormat.sampleRate,
        hardwareChannelCount: hardwareFormat.channelCount,
        clientSampleRate: format.sampleRate,
        clientChannelCount: format.channelCount
      )
    else {
      throw AudioCaptureError("The selected microphone format is still changing")
    }

    // When the default input device changes (for example AirPods disconnect),
    // the hardware format changes with it. A tap installed for the old format
    // would stop the engine from starting, so reinstall it against the current
    // format whenever the two no longer match.
    if tapInstalled, !matchesTapFormat(format) {
      input.removeTap(onBus: 0)
      tapInstalled = false
      tapFormat = nil
    }

    if !tapInstalled {
      input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
        guard let self else { return }
        let level = Self.rmsDB(buffer)
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate

        self.lock.lock()
        let bufferStartTime = self.totalCapturedTime
        self.totalCapturedTime += duration
        self.lastBufferReceivedAt = Date()
        let file = self.recordingFile
        if let file {
          do {
            try file.write(from: buffer)
          } catch {
            // The controller catches an unusable recording when transcription starts.
          }
        }
        self.lock.unlock()

        self.onBuffer?(buffer, bufferStartTime)
        if file != nil {
          self.onRecordingBuffer?(buffer)
        }
        self.onLevel?(level)
      }
      tapFormat = format
      tapInstalled = true
    }

    engine.prepare()
    try engine.start()
  }

  func beginRecording() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("voice-control-prototype", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("prompt-\(UUID().uuidString).wav")
    let format = engine.inputNode.outputFormat(forBus: 0)
    let file = try AVAudioFile(forWriting: url, settings: format.settings)

    lock.lock()
    recordingURL = url
    recordingFile = file
    lock.unlock()
  }

  func finishRecording() -> URL? {
    takeRecording()
  }

  func finishRecording(removingTailOf duration: TimeInterval) throws -> URL? {
    guard let recordingURL = takeRecording() else { return nil }
    do {
      return try RecordingTrimmer.trim(
        recordingURL,
        secondsToRemoveFromEnd: duration
      )
    } catch {
      try? FileManager.default.removeItem(at: recordingURL)
      throw error
    }
  }

  func stop() {
    lock.lock()
    recordingFile = nil
    recordingURL = nil
    lock.unlock()
    if tapInstalled {
      engine.inputNode.removeTap(onBus: 0)
      tapInstalled = false
      tapFormat = nil
    }
    engine.stop()
  }

  private func takeRecording() -> URL? {
    lock.lock()
    let url = recordingURL
    recordingFile = nil
    recordingURL = nil
    lock.unlock()
    return url
  }

  private func matchesTapFormat(_ format: AVAudioFormat) -> Bool {
    guard let tapFormat else { return false }
    return tapFormat.sampleRate == format.sampleRate
      && tapFormat.channelCount == format.channelCount
  }

  private static func rmsDB(_ buffer: AVAudioPCMBuffer) -> Float {
    guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return -120 }
    let samples = UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength))
    let meanSquare = samples.reduce(Float.zero) { $0 + ($1 * $1) } / Float(samples.count)
    return 20 * log10(max(sqrt(meanSquare), 0.000_001))
  }
}

enum AudioFormatReadiness {
  static func canInstallTap(
    hardwareSampleRate: Double,
    hardwareChannelCount: AVAudioChannelCount,
    clientSampleRate: Double,
    clientChannelCount: AVAudioChannelCount
  ) -> Bool {
    hardwareSampleRate > 0
      && hardwareChannelCount > 0
      && hardwareSampleRate == clientSampleRate
      && hardwareChannelCount == clientChannelCount
  }
}

enum RecordingTrimmer {
  static func trim(
    _ url: URL,
    secondsToRemoveFromEnd: TimeInterval
  ) throws -> URL {
    let source = try AVAudioFile(forReading: url)
    let frameCount = RecordingCutoff.frameCount(
      secondsToRemoveFromEnd: secondsToRemoveFromEnd,
      sampleRate: source.processingFormat.sampleRate,
      availableFrames: source.length
    )
    guard frameCount < source.length else { return url }

    let trimmedURL = url.deletingPathExtension()
      .appendingPathExtension("trimmed.wav")
    do {
      let destination = try AVAudioFile(
        forWriting: trimmedURL,
        settings: source.fileFormat.settings
      )
      let capacity = AVAudioFrameCount(min(4_096, max(frameCount, 1)))
      guard
        let buffer = AVAudioPCMBuffer(
          pcmFormat: source.processingFormat,
          frameCapacity: capacity
        )
      else {
        throw AudioCaptureError("Could not allocate the recording trim buffer")
      }

      var remaining = frameCount
      while remaining > 0 {
        let requested = AVAudioFrameCount(min(AVAudioFramePosition(capacity), remaining))
        try source.read(into: buffer, frameCount: requested)
        guard buffer.frameLength > 0 else { break }
        try destination.write(from: buffer)
        remaining -= AVAudioFramePosition(buffer.frameLength)
      }
      try FileManager.default.removeItem(at: url)
      return trimmedURL
    } catch {
      try? FileManager.default.removeItem(at: trimmedURL)
      throw error
    }
  }
}

enum RecordingCutoff {
  static func frameCount(
    secondsToRemoveFromEnd: TimeInterval,
    sampleRate: Double,
    availableFrames: AVAudioFramePosition
  ) -> AVAudioFramePosition {
    guard sampleRate > 0, availableFrames > 0 else { return 0 }
    let removedFrames = AVAudioFramePosition(
      (max(0, secondsToRemoveFromEnd) * sampleRate).rounded(.up)
    )
    return max(0, availableFrames - removedFrames)
  }
}

struct AudioCaptureError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}
