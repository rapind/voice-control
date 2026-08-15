@preconcurrency import AVFoundation
import Foundation

struct CorpusPrompt: Codable {
  let id: String
  let expected: String
  let audioFile: String
}

struct CorpusManifest: Codable {
  let inputDevice: String
  let recordedAt: Date
  let prompts: [CorpusPrompt]
}

struct WorkflowResult: Codable {
  let engine: String
  let promptID: String
  let audioDurationSeconds: Double
  let firstPreviewSeconds: Double?
  let finalizationSeconds: Double
  let totalSeconds: Double
  let transcript: String
}

enum ComparisonCorpus {
  static let prompts = [
    CorpusPrompt(
      id: "short",
      expected: "Send the message now.",
      audioFile: "short.wav"
    ),
    CorpusPrompt(
      id: "short-command",
      expected: "Open ChatGPT and summarize the latest response before I continue.",
      audioFile: "short-command.wav"
    ),
    CorpusPrompt(
      id: "medium",
      expected: "Refactor the Swift package so the command parser keeps its current behavior while supporting a second application target.",
      audioFile: "medium.wav"
    ),
    CorpusPrompt(
      id: "long",
      expected: "Review the current implementation, identify why live transcription sometimes revises earlier words, and propose the smallest change that improves responsiveness without weakening the final transcript or adding another configuration layer.",
      audioFile: "long.wav"
    ),
    CorpusPrompt(
      id: "extended",
      expected: "I want you to inspect the voice control workflow from wake detection through audio capture, live preview, final transcription, and text injection. Pay particular attention to cancellation, application focus changes, and anything that could send incomplete text to the wrong window. Explain the concrete failure modes first, then make only the changes that are justified by evidence.",
      audioFile: "extended.wav"
    ),
  ]
}

final class AudioBufferSink: @unchecked Sendable {
  let stream: AsyncStream<AVAudioPCMBuffer>

  private let lock = NSLock()
  private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

  init() {
    let pair = AsyncStream.makeStream(
      of: AVAudioPCMBuffer.self,
      bufferingPolicy: .unbounded
    )
    stream = pair.stream
    continuation = pair.continuation
  }

  func appendCopy(of buffer: AVAudioPCMBuffer) {
    lock.lock()
    let continuation = continuation
    lock.unlock()
    guard let continuation, let copy = buffer.workflowCopy() else { return }
    continuation.yield(copy)
  }

  func finish() {
    lock.lock()
    let continuation = continuation
    self.continuation = nil
    lock.unlock()
    continuation?.finish()
  }
}

extension AVAudioPCMBuffer {
  fileprivate func workflowCopy() -> AVAudioPCMBuffer? {
    guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
      return nil
    }
    copy.frameLength = frameLength
    let sourceBuffers = UnsafeMutableAudioBufferListPointer(mutableAudioBufferList)
    let destinationBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
    guard sourceBuffers.count == destinationBuffers.count else { return nil }
    for index in sourceBuffers.indices {
      let source = sourceBuffers[index]
      guard let sourceData = source.mData, let destinationData = destinationBuffers[index].mData
      else {
        return nil
      }
      memcpy(destinationData, sourceData, Int(source.mDataByteSize))
      destinationBuffers[index].mDataByteSize = source.mDataByteSize
    }
    return copy
  }
}

struct ProbeError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}

func seconds(from start: UInt64, to end: UInt64) -> Double {
  Double(end - start) / 1_000_000_000
}
