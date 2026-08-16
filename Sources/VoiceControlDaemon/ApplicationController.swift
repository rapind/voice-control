import AppKit
import ApplicationServices
import Foundation
import OSLog

struct CapturedApplication {
  let processIdentifier: pid_t
  let target: ApplicationTarget?
}

final class ApplicationController {
  private let logger = Logger(
    subsystem: "com.daverapin.voice-control-prototype",
    category: "ApplicationController"
  )

  func requestAccessibilityPermission() -> Bool {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
  }

  func captureTargetPID(for target: ApplicationTarget) -> pid_t? {
    if let frontmost = NSWorkspace.shared.frontmostApplication,
      isTarget(frontmost, target: target)
    {
      return frontmost.processIdentifier
    }
    return NSWorkspace.shared.runningApplications
      .first(where: { isTarget($0, target: target) })?
      .processIdentifier
  }

  func captureFrontmostApplication() -> CapturedApplication? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    return CapturedApplication(
      processIdentifier: app.processIdentifier,
      target: target(for: app)
    )
  }

  func focus(
    _ target: ApplicationTarget,
    targetPID: pid_t?, completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard AXIsProcessTrusted() else {
      completion(.failure(InjectionError("Accessibility permission is not granted")))
      return
    }
    guard let app = resolveTarget(target, pid: targetPID) else {
      completion(.failure(InjectionError("\(target.displayName) is not running")))
      return
    }

    logger.notice(
      "Targeting \(app.localizedName ?? "unknown", privacy: .public) pid=\(app.processIdentifier, privacy: .public)"
    )
    do {
      try requestFocus(app, target: target)
    } catch {
      completion(.failure(error))
      return
    }
    waitUntilFrontmost(app, attemptsRemaining: 40) { [weak self] focused in
      guard let self else { return }
      guard focused else {
        completion(
          .failure(InjectionError("\(target.displayName) did not become the frontmost app")))
        return
      }
      self.logger.notice("\(target.displayName, privacy: .public) is frontmost")
      completion(.success(()))
    }
  }

  func applyPreviewEdit(
    _ edit: PreviewEdit,
    targetPID: pid_t?
  ) -> Result<Void, Error> {
    guard AXIsProcessTrusted() else {
      return .failure(InjectionError("Accessibility permission is not granted"))
    }
    guard let targetPID,
      let app = NSRunningApplication(processIdentifier: targetPID),
      !app.isTerminated
    else {
      return .failure(InjectionError("The captured application is unavailable"))
    }
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
      return .failure(
        InjectionError("The captured application is no longer frontmost; transcription stopped"))
    }

    for _ in 0..<edit.deleteCount {
      guard postKey(keyCode: 51, flags: []) else {
        return .failure(InjectionError("Could not revise the live transcription"))
      }
    }
    guard edit.insertion.isEmpty || postText(edit.insertion) else {
      return .failure(InjectionError("Could not type the live transcription"))
    }
    return .success(())
  }

  func submitPreview(
    _ edit: PreviewEdit,
    finalText: String,
    targetPID: pid_t?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    if case .failure(let error) = applyPreviewEdit(edit, targetPID: targetPID) {
      completion(.failure(error))
      return
    }
    DispatchQueue.main.asyncAfter(
      deadline: .now() + SubmissionTiming.returnDelay(for: finalText)
    ) {
      guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
        completion(
          .failure(InjectionError("The captured application is no longer frontmost")))
        return
      }
      do {
        try self.pressReturnUsingSystemEvents()
        completion(.success(()))
      } catch {
        completion(.failure(error))
      }
    }
  }

  func execute(
    _ command: ApplicationCommand,
    for target: ApplicationTarget,
    targetPID: pid_t?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    if case .focus = command {
      focus(target, targetPID: targetPID, completion: completion)
      return
    }
    guard isFrontmostTarget(target, pid: targetPID) else {
      completion(
        .failure(InjectionError("\(target.displayName) is no longer the frontmost application")))
      return
    }
    if command == .newChat, target == .ghostty {
      guard postKey(keyCode: 17, flags: .maskCommand) else {
        completion(.failure(InjectionError("Could not create a new Ghostty tab")))
        return
      }
      pasteAndSubmit(
        "codex",
        to: target,
        delay: 0.6,
        completion: completion
      )
      return
    }
    guard let keyStroke = keyStroke(for: command, target: target) else {
      completion(.failure(InjectionError("Unsupported \(target.displayName) command")))
      return
    }
    guard postKey(keyCode: keyStroke.keyCode, flags: keyStroke.flags) else {
      completion(
        .failure(InjectionError("Could not send the \(target.displayName) keyboard command")))
      return
    }
    completion(.success(()))
  }

  private func requestFocus(_ app: NSRunningApplication, target: ApplicationTarget) throws {
    guard let bundleIdentifier = app.bundleIdentifier,
      target.bundleIdentifiers.contains(bundleIdentifier)
    else {
      throw InjectionError("The target is not a recognized \(target.displayName) application")
    }

    let source = "tell application id \"\(bundleIdentifier)\" to activate"
    guard let script = NSAppleScript(source: source) else {
      throw InjectionError("Could not create the \(target.displayName) activation request")
    }
    var errorInfo: NSDictionary?
    _ = script.executeAndReturnError(&errorInfo)
    if let errorInfo {
      let message =
        errorInfo[NSAppleScript.errorMessage] as? String
        ?? "macOS rejected the \(target.displayName) activation request"
      throw InjectionError(message)
    }
  }

  private func waitUntilFrontmost(
    _ app: NSRunningApplication,
    attemptsRemaining: Int,
    completion: @escaping (Bool) -> Void
  ) {
    if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
      completion(true)
      return
    }
    guard attemptsRemaining > 0, !app.isTerminated else {
      completion(false)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      self.waitUntilFrontmost(
        app,
        attemptsRemaining: attemptsRemaining - 1,
        completion: completion
      )
    }
  }

  private func resolveTarget(
    _ target: ApplicationTarget, pid: pid_t?
  ) -> NSRunningApplication? {
    if let pid,
      let app = NSRunningApplication(processIdentifier: pid),
      !app.isTerminated,
      isTarget(app, target: target)
    {
      return app
    }
    return NSWorkspace.shared.runningApplications.first(where: {
      isTarget($0, target: target)
    })
  }

  private func isTarget(_ app: NSRunningApplication, target: ApplicationTarget) -> Bool {
    if let identifier = app.bundleIdentifier, target.bundleIdentifiers.contains(identifier) {
      return true
    }
    return app.localizedName?.lowercased() == target.displayName.lowercased()
  }

  private func target(for app: NSRunningApplication) -> ApplicationTarget? {
    if let identifier = app.bundleIdentifier,
      let target = ApplicationTarget(bundleIdentifier: identifier)
    {
      return target
    }
    return ApplicationTarget.allCases.first(where: {
      app.localizedName?.lowercased() == $0.displayName.lowercased()
    })
  }

  private func isFrontmostTarget(_ target: ApplicationTarget, pid: pid_t?) -> Bool {
    guard let pid,
      let app = NSRunningApplication(processIdentifier: pid),
      !app.isTerminated,
      isTarget(app, target: target)
    else {
      return false
    }
    return NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
  }

  private func keyStroke(for command: ApplicationCommand, target: ApplicationTarget) -> (
    keyCode: CGKeyCode, flags: CGEventFlags
  )? {
    switch command {
    case .focus:
      return nil
    case .newChat:
      switch target {
      case .ghostty: return nil
      case .chatGPT: return (45, .maskCommand)
      case .chrome: return nil
      }
    case .focusItem(let number):
      let keyCodes: [Int: CGKeyCode] = [
        1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22, 7: 26, 8: 28, 9: 25,
      ]
      guard let keyCode = keyCodes[number] else { return nil }
      return (keyCode, .maskCommand)
    case .nextItem:
      guard target == .ghostty else { return nil }
      return (30, [.maskCommand, .maskShift])
    case .previousItem:
      guard target == .ghostty else { return nil }
      return (33, [.maskCommand, .maskShift])
    }
  }

  private func postKey(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
    guard let source = CGEventSource(stateID: .hidSystemState),
      let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    else {
      return false
    }
    down.flags = flags
    up.flags = flags
    down.post(tap: .cgSessionEventTap)
    up.post(tap: .cgSessionEventTap)
    return true
  }

  private func pressReturnUsingSystemEvents() throws {
    guard
      let script = NSAppleScript(
        source: "tell application id \"com.apple.systemevents\" to key code 36"
      )
    else {
      throw InjectionError("Could not create the Return key request")
    }
    var errorInfo: NSDictionary?
    _ = script.executeAndReturnError(&errorInfo)
    if let errorInfo {
      let message =
        errorInfo[NSAppleScript.errorMessage] as? String
        ?? "macOS rejected the Return key request"
      throw InjectionError(message)
    }
  }

  private func postText(_ text: String) -> Bool {
    guard let source = CGEventSource(stateID: .hidSystemState),
      let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
    else {
      return false
    }
    var characters = Array(text.utf16)
    down.keyboardSetUnicodeString(
      stringLength: characters.count,
      unicodeString: &characters
    )
    down.post(tap: .cgSessionEventTap)
    up.post(tap: .cgSessionEventTap)
    return true
  }

  private func pasteAndSubmit(
    _ text: String,
    to target: ApplicationTarget,
    delay: TimeInterval,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    let pasteboard = NSPasteboard.general
    let savedItems = copyPasteboardItems(pasteboard.pasteboardItems ?? [])
    pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else {
      completion(.failure(InjectionError("Could not place text on the clipboard")))
      return
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
      guard self.postKey(keyCode: 9, flags: .maskCommand) else {
        self.restorePasteboard(pasteboard, items: savedItems)
        completion(.failure(InjectionError("Could not send Command-V to \(target.displayName)")))
        return
      }
      DispatchQueue.main.asyncAfter(
        deadline: .now() + SubmissionTiming.returnDelay(for: text)
      ) {
        do {
          try self.pressReturnUsingSystemEvents()
        } catch {
          self.restorePasteboard(pasteboard, items: savedItems)
          completion(.failure(error))
          return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
          self.restorePasteboard(pasteboard, items: savedItems)
        }
        completion(.success(()))
      }
    }
  }

  private func copyPasteboardItems(_ items: [NSPasteboardItem]) -> [NSPasteboardItem] {
    items.map { source in
      let copy = NSPasteboardItem()
      for type in source.types {
        if let data = source.data(forType: type) {
          copy.setData(data, forType: type)
        }
      }
      return copy
    }
  }

  private func restorePasteboard(_ pasteboard: NSPasteboard, items: [NSPasteboardItem]) {
    pasteboard.clearContents()
    if !items.isEmpty {
      pasteboard.writeObjects(items)
    }
  }
}

enum SubmissionTiming {
  static func returnDelay(for text: String) -> TimeInterval {
    min(3, max(0.75, 0.5 + Double(text.utf16.count) / 200))
  }
}

struct PreviewEdit: Equatable {
  let deleteCount: Int
  let insertion: String
}

struct TranscriptPreview {
  private(set) var text = ""

  mutating func replace(with replacement: String) -> PreviewEdit {
    var previousIndex = text.startIndex
    var replacementIndex = replacement.startIndex
    while previousIndex < text.endIndex,
      replacementIndex < replacement.endIndex,
      text[previousIndex] == replacement[replacementIndex]
    {
      text.formIndex(after: &previousIndex)
      replacement.formIndex(after: &replacementIndex)
    }

    let edit = PreviewEdit(
      deleteCount: text[previousIndex...].count,
      insertion: String(replacement[replacementIndex...])
    )
    text = replacement
    return edit
  }
}

struct InjectionError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}
