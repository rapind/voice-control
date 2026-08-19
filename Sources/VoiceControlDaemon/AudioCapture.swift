import AVFoundation
import Foundation
import OSLog

final class AudioCapture {
  var onBuffer: ((AVAudioPCMBuffer, TimeInterval) -> Void)?
  var onRecordingBuffer: ((AVAudioPCMBuffer) -> Void)?
  var onLevel: ((Float) -> Void)?
  var onConfigurationChange: (() -> Void)?

  private let engine = AVAudioEngine()
  private let lock = NSLock()
  private let logger = Logger(
    subsystem: "com.daverapin.voice-control-prototype",
    category: "AudioCapture"
  )
  private var recordingFile: AVAudioFile?
  private var recordingURL: URL?
  private var totalCapturedTime: TimeInterval = 0
  private var tapInstalled = false
  private var tapFormat: AVAudioFormat?
  private var recordingFormat: AVAudioFormat?
  private var lastBufferReceivedAt: Date?
  private var loggedFirstBuffer = false
  private var configurationChangeObserver: NSObjectProtocol?

  init() {
    configurationChangeObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      self.logger.notice("Audio engine configuration changed")
      self.onConfigurationChange?()
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
    let clientFormat = input.outputFormat(forBus: 0)
    guard
      let formatPlan = AudioCaptureFormatPlan.make(
        hardwareFormat: hardwareFormat,
        clientFormat: clientFormat
      )
    else {
      throw AudioCaptureError("The selected microphone has no usable input format")
    }
    logger.notice(
      "Starting audio capture hardware=\(hardwareFormat.sampleRate, privacy: .public)Hz/\(hardwareFormat.channelCount, privacy: .public)ch client=\(clientFormat.sampleRate, privacy: .public)Hz/\(clientFormat.channelCount, privacy: .public)ch tap=\(formatPlan.tapFormat.sampleRate, privacy: .public)Hz/\(formatPlan.tapFormat.channelCount, privacy: .public)ch"
    )

    // When the default input device changes (for example AirPods disconnect),
    // the hardware format changes with it. A tap installed for the old format
    // would stop the engine from starting, so reinstall it against the current
    // format whenever the two no longer match.
    if tapInstalled, !matchesTapFormat(formatPlan.tapFormat) {
      input.removeTap(onBus: 0)
      tapInstalled = false
      tapFormat = nil
    }

    if !tapInstalled {
      input.installTap(onBus: 0, bufferSize: 512, format: formatPlan.tapFormat) {
        [weak self] buffer, _ in
        guard let self else { return }
        let level = Self.rmsDB(buffer)
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate

        self.lock.lock()
        let shouldLogFirstBuffer = !self.loggedFirstBuffer
        self.loggedFirstBuffer = true
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

        if shouldLogFirstBuffer {
          self.logger.notice(
            "Audio buffers started format=\(buffer.format.sampleRate, privacy: .public)Hz/\(buffer.format.channelCount, privacy: .public)ch"
          )
        }
        self.onBuffer?(buffer, bufferStartTime)
        if file != nil {
          self.onRecordingBuffer?(buffer)
        }
        self.onLevel?(level)
      }
      tapFormat = formatPlan.tapFormat
      tapInstalled = true
    }
    recordingFormat = formatPlan.recordingFormat

    engine.prepare()
    try engine.start()
    logger.notice("Audio engine started")
  }

  func beginRecording() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("voice-control-prototype", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("prompt-\(UUID().uuidString).wav")
    guard let format = recordingFormat else {
      throw AudioCaptureError("Audio capture has no active tap format")
    }
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
    loggedFirstBuffer = false
    lock.unlock()
    if tapInstalled {
      engine.inputNode.removeTap(onBus: 0)
      tapInstalled = false
      tapFormat = nil
    }
    recordingFormat = nil
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

struct AudioCaptureFormatPlan {
  let tapFormat: AVAudioFormat
  let recordingFormat: AVAudioFormat

  static func make(
    hardwareFormat: AVAudioFormat,
    clientFormat: AVAudioFormat
  ) -> AudioCaptureFormatPlan? {
    guard
      hardwareFormat.sampleRate > 0,
      hardwareFormat.channelCount > 0,
      clientFormat.sampleRate > 0,
      clientFormat.channelCount > 0
    else {
      return nil
    }
    return AudioCaptureFormatPlan(
      tapFormat: hardwareFormat,
      recordingFormat: hardwareFormat
    )
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
