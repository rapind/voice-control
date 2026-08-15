@preconcurrency import AVFoundation
import FluidAudio
import Foundation

private final class ParakeetPreviewCollector: @unchecked Sendable {
  private let lock = NSLock()
  private let startedAt: UInt64
  private var firstPreviewSeconds: Double?

  init(startedAt: UInt64) {
    self.startedAt = startedAt
  }

  func accept(_ text: String) {
    guard !text.isEmpty else { return }
    lock.lock()
    if firstPreviewSeconds == nil {
      firstPreviewSeconds = seconds(
        from: startedAt,
        to: DispatchTime.now().uptimeNanoseconds
      )
    }
    lock.unlock()
  }

  func firstPreview() -> Double? {
    lock.lock()
    defer { lock.unlock() }
    return firstPreviewSeconds
  }
}

actor ParakeetWorkflow {
  private let models: AsrModels
  private let finalManager: AsrManager

  init() async throws {
    let cacheDirectory = AsrModels.defaultCacheDirectory(for: .v3)
    guard AsrModels.modelsExist(at: cacheDirectory, version: .v3) else {
      throw ProbeError("No cached Parakeet v3 model was found at \(cacheDirectory.path)")
    }
    let models = try await AsrModels.load(from: cacheDirectory, version: .v3)
    let finalManager = AsrManager(config: .default)
    try await finalManager.loadModels(models)
    self.models = models
    self.finalManager = finalManager
  }

  func run(prompt: CorpusPrompt, fileURL: URL) async throws -> WorkflowResult {
    let audioFile = try AVAudioFile(forReading: fileURL)
    let format = audioFile.processingFormat
    let audioDuration = Double(audioFile.length) / format.sampleRate
    let liveManager = AsrManager(config: .default)
    try await liveManager.loadModels(models)
    let sink = AudioBufferSink()
    let startedAt = DispatchTime.now().uptimeNanoseconds
    let collector = ParakeetPreviewCollector(startedAt: startedAt)
    let liveTask = Task {
      let converter = AudioConverter()
      var samples: [Float] = []
      samples.reserveCapacity(16_000 * 60)
      let updateIntervalSamples = 24_000
      var nextUpdateSampleCount = updateIntervalSamples
      let decoderLayerCount = await liveManager.decoderLayerCount

      do {
        for await buffer in sink.stream {
          try Task.checkCancellation()
          samples.append(contentsOf: try converter.resampleBuffer(buffer))
          guard samples.count >= nextUpdateSampleCount else { continue }
          nextUpdateSampleCount = samples.count + updateIntervalSamples
          var decoderState = TdtDecoderState.make(decoderLayers: decoderLayerCount)
          let result = try await liveManager.transcribe(
            samples,
            decoderState: &decoderState,
            language: .english
          )
          try Task.checkCancellation()
          collector.accept(result.text)
        }
      } catch is CancellationError {
        return
      } catch {
        return
      }
    }

    while audioFile.framePosition < audioFile.length {
      let remaining = audioFile.length - audioFile.framePosition
      let frameCount = AVAudioFrameCount(min(4_096, remaining))
      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        throw ProbeError("Could not allocate a Parakeet input buffer")
      }
      try audioFile.read(into: buffer, frameCount: frameCount)
      sink.appendCopy(of: buffer)
      let duration = Double(buffer.frameLength) / format.sampleRate
      try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    }

    let audioEndedAt = DispatchTime.now().uptimeNanoseconds
    sink.finish()
    liveTask.cancel()
    await liveTask.value
    await liveManager.cleanup()

    var decoderState = TdtDecoderState.make(
      decoderLayers: await finalManager.decoderLayerCount
    )
    let final = try await finalManager.transcribe(
      fileURL,
      decoderState: &decoderState,
      language: .english
    )
    let finishedAt = DispatchTime.now().uptimeNanoseconds
    return WorkflowResult(
      engine: "parakeet-rolling-plus-final",
      promptID: prompt.id,
      audioDurationSeconds: audioDuration,
      firstPreviewSeconds: collector.firstPreview(),
      finalizationSeconds: seconds(from: audioEndedAt, to: finishedAt),
      totalSeconds: seconds(from: startedAt, to: finishedAt),
      transcript: final.text
    )
  }
}
