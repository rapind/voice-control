import AppKit
import ApplicationServices
import Foundation
import OSLog

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

  func inject(
    _ text: String,
    into target: ApplicationTarget,
    targetPID: pid_t?, completion: @escaping (Result<Void, Error>) -> Void
  ) {
    focus(target, targetPID: targetPID) { [weak self] focusResult in
      guard let self else { return }
      if case .failure(let error) = focusResult {
        completion(.failure(error))
        return
      }

      self.pasteAndSubmit(text, to: target, delay: 0.15, completion: completion)
    }
  }

  func execute(
    _ command: ApplicationCommand,
    for target: ApplicationTarget,
    targetPID: pid_t?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    focus(target, targetPID: targetPID) { [weak self] focusResult in
      guard let self else { return }
      if case .failure(let error) = focusResult {
        completion(.failure(error))
        return
      }
      guard command != .focus else {
        completion(.success(()))
        return
      }
      if command == .newChat, target == .ghostty {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          guard self.postKey(keyCode: 17, flags: .maskCommand) else {
            completion(.failure(InjectionError("Could not create a new Ghostty tab")))
            return
          }
          self.pasteAndSubmit("codex", to: target, delay: 0.6, completion: completion)
        }
        return
      }
      guard let keyStroke = self.keyStroke(for: command, target: target) else {
        completion(.failure(InjectionError("Unsupported \(target.displayName) command")))
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        guard self.postKey(keyCode: keyStroke.keyCode, flags: keyStroke.flags) else {
          completion(
            .failure(InjectionError("Could not send the \(target.displayName) keyboard command")))
          return
        }
        completion(.success(()))
      }
    }
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
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
        guard self.postKey(keyCode: 36, flags: []) else {
          self.restorePasteboard(pasteboard, items: savedItems)
          completion(.failure(InjectionError("Could not send Return to \(target.displayName)")))
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

struct InjectionError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}
