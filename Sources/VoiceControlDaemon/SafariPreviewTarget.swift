import AppKit
import ApplicationServices
import Foundation

struct PreviewFieldEdit: Equatable {
  let afterDeletion: String
  let afterInsertion: String

  init(text: String, selection: NSRange, edit: PreviewEdit) throws {
    guard edit.deleteCount >= 0, selection.location >= 0, selection.length >= 0,
      selection.location <= text.utf16.count,
      selection.length <= text.utf16.count - selection.location,
      let range = Range(selection, in: text),
      range.lowerBound.samePosition(in: text) != nil,
      range.upperBound.samePosition(in: text) != nil
    else { throw InjectionError("The text field returned an invalid selection") }

    var prefix = String(text[..<range.lowerBound])
    let suffix = String(text[range.upperBound...])
    if edit.deleteCount > 0 {
      // Backspace removes an existing selection before deleting preceding characters.
      prefix = String(prefix.dropLast(edit.deleteCount - (range.isEmpty ? 0 : 1)))
    }
    afterDeletion = edit.deleteCount > 0 ? prefix + suffix : text
    afterInsertion = edit.insertion.isEmpty ? afterDeletion : prefix + edit.insertion + suffix
  }
}

// WebKit can reorder overlapping Unicode key events. Observe each edit before
// posting the next one, including the deletion that precedes replacement text.
struct SafariPreviewTarget {
  let edit: PreviewFieldEdit
  private let field: AXUIElement
  private let application: AXUIElement
  private let pid: pid_t

  static func requiresAcknowledgement(bundleIdentifier: String?) -> Bool {
    guard let bundleIdentifier else { return false }
    return bundleIdentifier == "com.apple.Safari"
      || bundleIdentifier == "com.apple.SafariTechnologyPreview"
      || bundleIdentifier.hasPrefix("com.apple.Safari.WebApp.")
  }

  init(pid: pid_t, edit: PreviewEdit) throws {
    self.pid = pid
    application = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(application, 0.1)
    var focused: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        application, kAXFocusedUIElementAttribute as CFString, &focused
      ) == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
    else { throw InjectionError("Could not read Safari's focused text field") }
    field = focused as! AXUIElement
    AXUIElementSetMessagingTimeout(field, 0.1)
    var value: CFTypeRef?
    var selected: CFTypeRef?
    guard AXUIElementCopyAttributeValue(field, kAXValueAttribute as CFString, &value) == .success,
      let text = value as? String,
      AXUIElementCopyAttributeValue(
        field, kAXSelectedTextRangeAttribute as CFString, &selected
      ) == .success, let selected, CFGetTypeID(selected) == AXValueGetTypeID()
    else { throw InjectionError("Safari did not expose editable text and its selection") }
    var selection = CFRange()
    guard AXValueGetValue(selected as! AXValue, .cfRange, &selection)
    else { throw InjectionError("Could not read Safari's text selection") }
    self.edit = try PreviewFieldEdit(
      text: text, selection: NSRange(location: selection.location, length: selection.length),
      edit: edit)
  }

  func wait(for expected: String) throws {
    let deadline = ProcessInfo.processInfo.systemUptime + 0.75
    repeat {
      guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
      else { throw InjectionError("The captured application is no longer frontmost") }
      var value: CFTypeRef?
      let result = AXUIElementCopyAttributeValue(field, kAXValueAttribute as CFString, &value)
      if result == .success, let actual = value as? String, actual == expected {
        var focused: CFTypeRef?
        guard
          AXUIElementCopyAttributeValue(
            application, kAXFocusedUIElementAttribute as CFString, &focused
          ) == .success, let focused, CFEqual(focused, field)
        else { throw InjectionError("Safari's focused text field changed during transcription") }
        return
      }
      guard result == .success || result == .cannotComplete
      else { throw InjectionError("Safari's text field became unavailable during transcription") }
      Thread.sleep(forTimeInterval: 0.001)
    } while ProcessInfo.processInfo.systemUptime < deadline
    throw InjectionError("Safari did not acknowledge the live transcription edit")
  }
}
