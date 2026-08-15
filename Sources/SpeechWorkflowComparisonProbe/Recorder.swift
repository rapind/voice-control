@preconcurrency import AVFoundation
import Foundation

final class CorpusRecorder {
  private let engine = AVAudioEngine()
  private var recordingFile: AVAudioFile?

  static func requestPermission() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      return true
    case .notDetermined:
      return await withCheckedContinuation { continuation in
        AVCaptureDevice.requestAccess(for: .audio) { granted in
          continuation.resume(returning: granted)
        }
      }
    default:
      return false
    }
  }

  func record(to fileURL: URL) throws {
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw ProbeError("The selected microphone has no usable input format")
    }

    recordingFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)
    input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
      try? self?.recordingFile?.write(from: buffer)
    }
    engine.prepare()
    try engine.start()
  }

  func stop() {
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    recordingFile = nil
  }
}

func recordCorpus(in directory: URL) async throws -> URL {
  guard await CorpusRecorder.requestPermission() else {
    throw ProbeError("Microphone permission was denied")
  }
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

  let inputDevice = AVCaptureDevice.default(for: .audio)?.localizedName ?? "Unknown default input"
  print("Detected default microphone: \(inputDevice)")
  print("Confirm this is your AirPods microphone before continuing.")
  print("Press Return to continue, or Ctrl-C to stop and change the macOS Sound input.")
  _ = readLine()

  let recorder = CorpusRecorder()
  for (index, prompt) in ComparisonCorpus.prompts.enumerated() {
    print("\nPrompt \(index + 1) of \(ComparisonCorpus.prompts.count), \(prompt.id):")
    print(prompt.expected)
    print("\nPress Return to start recording.")
    _ = readLine()
    let fileURL = directory.appendingPathComponent(prompt.audioFile)
    try recorder.record(to: fileURL)
    print("Recording. Speak naturally, then press Return to stop.")
    _ = readLine()
    recorder.stop()
  }

  let manifest = CorpusManifest(
    inputDevice: inputDevice,
    recordedAt: Date(),
    prompts: ComparisonCorpus.prompts
  )
  let manifestURL = directory.appendingPathComponent("manifest.json")
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
  print("\nCorpus saved to \(directory.path)")
  return manifestURL
}
