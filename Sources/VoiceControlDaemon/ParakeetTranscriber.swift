import FluidAudio
import Foundation

actor ParakeetTranscriber {
  private var manager: AsrManager?

  func prepare() async throws {
    let cacheDirectory = AsrModels.defaultCacheDirectory(for: .v3)
    guard AsrModels.modelsExist(at: cacheDirectory, version: .v3) else {
      throw ParakeetError(
        "No cached Parakeet v3 model was found at \(cacheDirectory.path). "
          + "Open TypeWhisper and load Parakeet once before starting this prototype."
      )
    }

    let models = try await AsrModels.load(
      from: cacheDirectory,
      version: .v3
    )
    let manager = AsrManager(config: .default)
    try await manager.loadModels(models)
    self.manager = manager
  }

  func transcribe(fileURL: URL) async throws -> String {
    guard let manager else {
      throw ParakeetError("Parakeet is not loaded")
    }

    var decoderState = TdtDecoderState.make(
      decoderLayers: await manager.decoderLayerCount
    )
    let result = try await manager.transcribe(
      fileURL,
      decoderState: &decoderState,
      language: .english
    )
    return result.text
  }
}

struct ParakeetError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}
