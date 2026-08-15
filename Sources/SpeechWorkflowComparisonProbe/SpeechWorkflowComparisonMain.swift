import Foundation

@main
struct SpeechWorkflowComparisonProbe {
  static func main() async {
    guard #available(macOS 26.0, *) else {
      fputs("SpeechWorkflowComparisonProbe requires macOS 26.\n", stderr)
      exit(1)
    }

    do {
      guard CommandLine.arguments.count >= 2 else {
        throw ProbeError(
          "Use record, compare <manifest>, warmup <engine> <manifest>, "
            + "or stress <engine> <manifest> <repeats>"
        )
      }
      switch CommandLine.arguments[1] {
      case "record":
        let directory: URL
        if CommandLine.arguments.count >= 3 {
          directory = URL(fileURLWithPath: CommandLine.arguments[2])
        } else {
          let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
          directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(
              ".build/speech-workflow-comparison/airpods-\(timestamp)",
              isDirectory: true
            )
        }
        let manifest = try await recordCorpus(in: directory)
        print("MANIFEST: \(manifest.path)")

      case "compare":
        guard CommandLine.arguments.count >= 3 else {
          throw ProbeError("compare requires a manifest path")
        }
        try await compare(
          manifestURL: URL(fileURLWithPath: CommandLine.arguments[2])
        )

      case "warmup":
        guard CommandLine.arguments.count >= 4 else {
          throw ProbeError("warmup requires apple|parakeet and a manifest path")
        }
        try await warmup(
          engine: CommandLine.arguments[2],
          manifestURL: URL(fileURLWithPath: CommandLine.arguments[3])
        )

      case "stress":
        guard
          CommandLine.arguments.count >= 5,
          let repeats = Int(CommandLine.arguments[4]),
          repeats > 0
        else {
          throw ProbeError("stress requires apple|parakeet, a manifest path, and repeat count")
        }
        try await stress(
          engine: CommandLine.arguments[2],
          manifestURL: URL(fileURLWithPath: CommandLine.arguments[3]),
          repeats: repeats
        )

      default:
        throw ProbeError("Unknown mode \(CommandLine.arguments[1])")
      }
    } catch {
      fputs("ERROR: \(error.localizedDescription)\n", stderr)
      exit(1)
    }
  }

  @available(macOS 26.0, *)
  private static func compare(manifestURL: URL) async throws {
    let manifest = try loadManifest(manifestURL)
    let directory = manifestURL.deletingLastPathComponent()
    print("Input device: \(manifest.inputDevice)")
    print("Preparing both engines...")
    let apple = try await AppleWorkflow()
    let parakeet = try await ParakeetWorkflow()
    let outputURL = directory.appendingPathComponent("workflow-results.jsonl")
    try? FileManager.default.removeItem(at: outputURL)

    for prompt in manifest.prompts {
      let fileURL = directory.appendingPathComponent(prompt.audioFile)
      print("Replaying \(prompt.id) through Apple progressive transcription...")
      let appleResult = try await apple.run(prompt: prompt, fileURL: fileURL)
      try append(appleResult, to: outputURL)
      printResult(appleResult)

      print("Replaying \(prompt.id) through Parakeet rolling and final transcription...")
      let parakeetResult = try await parakeet.run(prompt: prompt, fileURL: fileURL)
      try append(parakeetResult, to: outputURL)
      printResult(parakeetResult)
    }
    print("Results: \(outputURL.path)")
  }
  @available(macOS 26.0, *)
  private static func warmup(engine: String, manifestURL: URL) async throws {
    let manifest = try loadManifest(manifestURL)
    guard let prompt = manifest.prompts.first else {
      throw ProbeError("The corpus manifest contains no prompts")
    }
    let fileURL = manifestURL.deletingLastPathComponent()
      .appendingPathComponent(prompt.audioFile)
    switch engine {
    case "apple":
      _ = try await AppleWorkflow().run(prompt: prompt, fileURL: fileURL)
    case "parakeet":
      _ = try await ParakeetWorkflow().run(prompt: prompt, fileURL: fileURL)
    default:
      throw ProbeError("Unknown engine \(engine)")
    }
    print("WARMUP_RESULT engine=\(engine)")
  }


  @available(macOS 26.0, *)
  private static func stress(engine: String, manifestURL: URL, repeats: Int) async throws {
    let manifest = try loadManifest(manifestURL)
    let directory = manifestURL.deletingLastPathComponent()
    var characters = 0

    switch engine {
    case "apple":
      let workflow = try await AppleWorkflow()
      for repeatIndex in 1...repeats {
        for prompt in manifest.prompts {
          let result = try await workflow.run(
            prompt: prompt,
            fileURL: directory.appendingPathComponent(prompt.audioFile)
          )
          characters += result.transcript.count
        }
        print("Apple corpus \(repeatIndex)/\(repeats)")
      }
    case "parakeet":
      let workflow = try await ParakeetWorkflow()
      for repeatIndex in 1...repeats {
        for prompt in manifest.prompts {
          let result = try await workflow.run(
            prompt: prompt,
            fileURL: directory.appendingPathComponent(prompt.audioFile)
          )
          characters += result.transcript.count
        }
        print("Parakeet corpus \(repeatIndex)/\(repeats)")
      }
    default:
      throw ProbeError("Unknown engine \(engine)")
    }
    print("STRESS_RESULT engine=\(engine) repeats=\(repeats) characters=\(characters)")
  }

  private static func loadManifest(_ url: URL) throws -> CorpusManifest {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(CorpusManifest.self, from: Data(contentsOf: url))
  }

  private static func append(_ result: WorkflowResult, to url: URL) throws {
    let data = try JSONEncoder().encode(result) + Data("\n".utf8)
    if FileManager.default.fileExists(atPath: url.path) {
      let handle = try FileHandle(forWritingTo: url)
      try handle.seekToEnd()
      try handle.write(contentsOf: data)
      try handle.close()
    } else {
      try data.write(to: url, options: .atomic)
    }
  }

  private static func printResult(_ result: WorkflowResult) {
    let preview = result.firstPreviewSeconds
      .map { String(format: "%.3f", $0) } ?? "none"
    print(
      "  \(result.engine): preview=\(preview)s "
        + "finalize=\(String(format: "%.3f", result.finalizationSeconds))s"
    )
    print("  \(result.transcript)")
  }
}
