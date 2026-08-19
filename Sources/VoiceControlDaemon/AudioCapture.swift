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
  private var recordingStartAudioTime: TimeInterval?
  private var totalCapturedTime: TimeInterval = 0
  private var tapInstalled = false
  private var tapFormat: AVAudioFormat?
  private var recordingFormat: AVAudioFormat?
  private var lastBufferReceivedAt: Date?
  private var loggedFirstBuffer = false
  private var configurationChangeObserver: NSObjectProtocol?
  private var voiceProcessingEnabled: Bool

  init(voiceProcessingEnabled: Bool = false) {
    self.voiceProcessingEnabled = voiceProcessingEnabled
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

  func setVoiceProcessingEnabled(_ enabled: Bool) {
    precondition(!engine.isRunning, "Voice processing can only change while audio is stopped")
    voiceProcessingEnabled = enabled
  }

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
    if input.isVoiceProcessingEnabled != voiceProcessingEnabled {
      try input.setVoiceProcessingEnabled(voiceProcessingEnabled)
      let state = voiceProcessingEnabled ? "enabled" : "disabled"
      logger.notice(
        "Apple voice processing \(state, privacy: .public)"
      )
    }
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
      let deliveryFormat = formatPlan.recordingFormat
      input.installTap(onBus: 0, bufferSize: 512, format: formatPlan.tapFormat) {
        [weak self] buffer, _ in
        guard let self else { return }
        guard
          let deliveryBuffer = AudioCaptureBufferNormalizer.normalize(
            buffer,
            outputFormat: deliveryFormat
          )
        else {
          self.logger.error(
            "Could not normalize \(buffer.format.channelCount, privacy: .public)-channel audio for speech recognition"
          )
          return
        }
        let level = Self.rmsDB(deliveryBuffer)
        let duration = Double(deliveryBuffer.frameLength) / deliveryBuffer.format.sampleRate

        self.lock.lock()
        let shouldLogFirstBuffer = !self.loggedFirstBuffer
        self.loggedFirstBuffer = true
        let bufferStartTime = self.totalCapturedTime
        self.totalCapturedTime += duration
        self.lastBufferReceivedAt = Date()
        let file = self.recordingFile
        if let file {
          do {
            try file.write(from: deliveryBuffer)
          } catch {
            // The controller catches an unusable recording when transcription starts.
          }
        }
        self.lock.unlock()

        if shouldLogFirstBuffer {
          self.logger.notice(
            "Audio buffers started source=\(buffer.format.sampleRate, privacy: .public)Hz/\(buffer.format.channelCount, privacy: .public)ch delivery=\(deliveryBuffer.format.sampleRate, privacy: .public)Hz/\(deliveryBuffer.format.channelCount, privacy: .public)ch"
          )
        }
        self.onBuffer?(deliveryBuffer, bufferStartTime)
        if file != nil {
          self.onRecordingBuffer?(deliveryBuffer)
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
    recordingStartAudioTime = totalCapturedTime
    lock.unlock()
  }

  func finishRecording() -> URL? {
    takeRecording()?.url
  }

  func finishRecording(endingAtAudioTime cutoffAudioTime: TimeInterval) throws -> URL? {
    guard let recording = takeRecording() else { return nil }
    let durationToKeep = RecordingCutoff.durationToKeep(
      recordingStartAudioTime: recording.startAudioTime,
      controlPhraseStartAudioTime: cutoffAudioTime,
      safetyMargin: 0.12
    )
    do {
      return try RecordingTrimmer.trim(
        recording.url,
        keepingFirst: durationToKeep
      )
    } catch {
      try? FileManager.default.removeItem(at: recording.url)
      throw error
    }
  }

  func stop() {
    lock.lock()
    recordingFile = nil
    recordingURL = nil
    recordingStartAudioTime = nil
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

  private func takeRecording() -> (url: URL, startAudioTime: TimeInterval)? {
    lock.lock()
    let url = recordingURL
    let startAudioTime = recordingStartAudioTime
    recordingFile = nil
    recordingURL = nil
    recordingStartAudioTime = nil
    lock.unlock()
    guard let url, let startAudioTime else { return nil }
    return (url, startAudioTime)
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

struct AmbientNoiseFloor {
  private(set) var estimateDB: Float?
  private(set) var sampleCount = 0

  var isCalibrated: Bool { sampleCount >= 50 }

  mutating func observe(_ levelDB: Float) {
    guard levelDB.isFinite, (-120...0).contains(levelDB) else { return }
    sampleCount += 1
    guard let estimateDB else {
      self.estimateDB = levelDB
      return
    }

    // Follow quieter samples quickly, but let the estimate rise very slowly.
    // Speech therefore does not become part of the measured room noise floor.
    let smoothing: Float = levelDB < estimateDB ? 0.2 : 0.002
    self.estimateDB = estimateDB + smoothing * (levelDB - estimateDB)
  }

  func speechThreshold(fallback: Float) -> Float {
    guard isCalibrated, let estimateDB else { return fallback }
    return min(-25, max(-65, estimateDB + 8))
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
    let recordingFormat: AVAudioFormat
    if hardwareFormat.channelCount == 1 {
      recordingFormat = hardwareFormat
    } else {
      guard
        let monoFormat = AVAudioFormat(
          standardFormatWithSampleRate: hardwareFormat.sampleRate,
          channels: 1
        )
      else {
        return nil
      }
      recordingFormat = monoFormat
    }
    return AudioCaptureFormatPlan(
      tapFormat: hardwareFormat,
      recordingFormat: recordingFormat
    )
  }
}

enum AudioCaptureBufferNormalizer {
  static func normalize(
    _ input: AVAudioPCMBuffer,
    outputFormat: AVAudioFormat
  ) -> AVAudioPCMBuffer? {
    guard
      outputFormat.channelCount == 1,
      input.format.sampleRate == outputFormat.sampleRate,
      let sourceChannels = input.floatChannelData
    else {
      return nil
    }
    if input.format.channelCount == 1 {
      return input
    }
    guard
      let output = AVAudioPCMBuffer(
        pcmFormat: outputFormat,
        frameCapacity: input.frameLength
      ),
      let destinationChannels = output.floatChannelData
    else {
      return nil
    }
    output.frameLength = input.frameLength
    destinationChannels[0].update(
      from: sourceChannels[0],
      count: Int(input.frameLength)
    )
    return output
  }
}

enum RecordingTrimmer {
  static func trim(
    _ url: URL,
    keepingFirst duration: TimeInterval
  ) throws -> URL {
    let source = try AVAudioFile(forReading: url)
    let frameCount = RecordingCutoff.frameCountToKeep(
      duration: duration,
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
  static func durationToKeep(
    recordingStartAudioTime: TimeInterval,
    controlPhraseStartAudioTime: TimeInterval,
    safetyMargin: TimeInterval
  ) -> TimeInterval {
    max(0, controlPhraseStartAudioTime - recordingStartAudioTime - max(0, safetyMargin))
  }

  static func frameCountToKeep(
    duration: TimeInterval,
    sampleRate: Double,
    availableFrames: AVAudioFramePosition
  ) -> AVAudioFramePosition {
    guard sampleRate > 0, availableFrames > 0 else { return 0 }
    let retainedFrames = AVAudioFramePosition(
      (max(0, duration) * sampleRate).rounded(.down)
    )
    return min(availableFrames, retainedFrames)
  }
}

struct AudioCaptureError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}
