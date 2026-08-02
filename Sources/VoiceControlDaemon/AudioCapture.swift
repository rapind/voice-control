import AVFoundation
import Foundation

final class AudioCapture {
  var onBuffer: ((AVAudioPCMBuffer) -> Void)?
  var onLevel: ((Float) -> Void)?

  private let engine = AVAudioEngine()
  private let lock = NSLock()
  private var recordingFile: AVAudioFile?
  private var recordingURL: URL?
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
        self.onBuffer?(buffer)
        self.onLevel?(level)

        self.lock.lock()
        let file = self.recordingFile
        if let file {
          do {
            try file.write(from: buffer)
          } catch {
            // The controller catches an unusable recording when transcription starts.
          }
        }
        self.lock.unlock()
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
    lock.lock()
    let url = recordingURL
    recordingFile = nil
    recordingURL = nil
    lock.unlock()
    return url
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

  private static func rmsDB(_ buffer: AVAudioPCMBuffer) -> Float {
    guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return -120 }
    let samples = UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength))
    let meanSquare = samples.reduce(Float.zero) { $0 + ($1 * $1) } / Float(samples.count)
    return 20 * log10(max(sqrt(meanSquare), 0.000_001))
  }
}

struct AudioCaptureError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}
