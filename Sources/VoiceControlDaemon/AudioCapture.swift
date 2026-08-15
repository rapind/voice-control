import AVFoundation
import Foundation

final class AudioCapture {
  var onBuffer: ((AVAudioPCMBuffer, TimeInterval) -> Void)?
  var onRecordingBuffer: ((AVAudioPCMBuffer) -> Void)?
  var onLevel: ((Float) -> Void)?

  private let engine = AVAudioEngine()
  private let lock = NSLock()
  private var recordingFile: AVAudioFile?
  private var recordingURL: URL?
  private var totalCapturedTime: TimeInterval = 0
  private var tapInstalled = false

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
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw AudioCaptureError("The selected microphone has no usable input format")
    }

    if !tapInstalled {
      input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
        guard let self else { return }
        let level = Self.rmsDB(buffer)
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate

        self.lock.lock()
        let bufferStartTime = self.totalCapturedTime
        self.totalCapturedTime += duration
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

  private static func rmsDB(_ buffer: AVAudioPCMBuffer) -> Float {
    guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return -120 }
    let samples = UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength))
    let meanSquare = samples.reduce(Float.zero) { $0 + ($1 * $1) } / Float(samples.count)
    return 20 * log10(max(sqrt(meanSquare), 0.000_001))
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
