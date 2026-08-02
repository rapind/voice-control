import AVFoundation
import Foundation
import OSLog
import Speech

final class KeywordListener {
  var onTranscript: ((String) -> Void)?
  var onError: ((String) -> Void)?

  private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
  private let logger = Logger(
    subsystem: "com.daverapin.voice-control-prototype",
    category: "KeywordListener"
  )
  private var contextualStrings: [String]
  private let lock = NSLock()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var recycleTimer: Timer?
  private var generation = 0
  private(set) var isListening = false

  init(contextualStrings: [String]) {
    self.contextualStrings = contextualStrings
  }

  static func requestPermission(_ completion: @escaping (Bool) -> Void) {
    SFSpeechRecognizer.requestAuthorization { status in
      DispatchQueue.main.async {
        completion(status == .authorized)
      }
    }
  }

  func start() throws {
    dispatchPrecondition(condition: .onQueue(.main))
    guard !isListening else { return }
    guard let recognizer, recognizer.isAvailable else {
      throw KeywordError("Apple Speech recognizer is unavailable")
    }
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
    request.contextualStrings = contextualStrings
    if #available(macOS 15.0, *) {
      request.addsPunctuation = false
    }

    lock.lock()
    self.request = request
    lock.unlock()
    isListening = true
    generation += 1
    let currentGeneration = generation

    task = recognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self else { return }
      DispatchQueue.main.async {
        guard self.isListening, self.generation == currentGeneration else { return }
        if let result {
          let transcript = result.bestTranscription.formattedString
          self.onTranscript?(transcript)
        }
        if let error {
          let nsError = error as NSError
          self.logger.error(
            "Apple Speech error \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public): \(error.localizedDescription, privacy: .public)"
          )
          if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 216 {
            return
          }
          self.onError?(error.localizedDescription)
        }
      }
    }

    recycleTimer?.invalidate()
    let timer = Timer(timeInterval: 45, repeats: false) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self, self.isListening else { return }
        self.stop()
        try? self.start()
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    recycleTimer = timer
  }

  func updateContextualStrings(_ contextualStrings: [String]) throws {
    dispatchPrecondition(condition: .onQueue(.main))
    guard contextualStrings != self.contextualStrings else { return }
    let previousContextualStrings = self.contextualStrings
    let wasListening = isListening
    if wasListening {
      stop()
    }
    self.contextualStrings = contextualStrings
    if wasListening {
      do {
        try start()
      } catch {
        self.contextualStrings = previousContextualStrings
        try? start()
        throw error
      }
    }
  }

  func stop() {
    dispatchPrecondition(condition: .onQueue(.main))
    recycleTimer?.invalidate()
    recycleTimer = nil
    isListening = false
    generation += 1
    lock.lock()
    request?.endAudio()
    request = nil
    lock.unlock()
    task?.cancel()
    task = nil
  }

  func append(_ buffer: AVAudioPCMBuffer) {
    lock.lock()
    let currentRequest = request
    lock.unlock()
    currentRequest?.append(buffer)
  }
}

struct KeywordError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}
