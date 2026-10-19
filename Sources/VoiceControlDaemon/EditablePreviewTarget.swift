import AppKit
import ApplicationServices
import Foundation

struct PreviewFieldEdit: Equatable {
  let replacementRange: NSRange
  let afterDeletion: String
  let afterInsertion: String
  private let insertionWithoutEmptyParagraph: String?

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
    replacementRange = NSRange(
      location: prefix.utf16.count,
      length: selection.location + selection.length - prefix.utf16.count)
    afterDeletion = edit.deleteCount > 0 ? prefix + suffix : text
    afterInsertion = edit.insertion.isEmpty ? afterDeletion : prefix + edit.insertion + suffix
    // An empty rich-text paragraph can expose a newline through Accessibility,
    // then drop that newline on the first insertion. Accept either representation
    // only for this empty baseline, without trimming real text or inserted newlines.
    insertionWithoutEmptyParagraph =
      text == "\n" && selection == NSRange(location: 0, length: 0)
        && edit.deleteCount == 0 && !edit.insertion.isEmpty ? edit.insertion : nil
  }

  func acknowledgesInsertion(_ actual: String) -> Bool {
    actual == afterInsertion || actual == insertionWithoutEmptyParagraph
  }
}

// Clients process native input asynchronously. Observe each edit before
// posting the next one, and replace corrections as a single selected range.
struct EditablePreviewTarget {
  let edit: PreviewFieldEdit
  private let field: AXUIElement
  private let application: AXUIElement
  private let pid: pid_t
  private let originalText: String

  init(pid: pid_t, edit: PreviewEdit) throws {
    self.pid = pid
    application = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(application, 0.1)
    var focused: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        application, kAXFocusedUIElementAttribute as CFString, &focused
      ) == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
    else { throw InjectionError("Could not read the client's focused text field") }
    field = focused as! AXUIElement
    AXUIElementSetMessagingTimeout(field, 0.1)
    var selectionSettable = DarwinBoolean(false)
    guard
      AXUIElementIsAttributeSettable(
        field, kAXSelectedTextRangeAttribute as CFString, &selectionSettable) == .success,
      selectionSettable.boolValue
    else {
      throw InjectionError("The client does not expose a writable text selection")
    }
    var value: CFTypeRef?
    var selected: CFTypeRef?
    guard AXUIElementCopyAttributeValue(field, kAXValueAttribute as CFString, &value) == .success,
      let text = value as? String,
      AXUIElementCopyAttributeValue(
        field, kAXSelectedTextRangeAttribute as CFString, &selected
      ) == .success, let selected, CFGetTypeID(selected) == AXValueGetTypeID()
    else { throw InjectionError("The client did not expose editable text and its selection") }
    var selection = CFRange()
    guard AXValueGetValue(selected as! AXValue, .cfRange, &selection)
    else { throw InjectionError("Could not read the client's text selection") }
    originalText = text
    self.edit = try PreviewFieldEdit(
      text: text, selection: NSRange(location: selection.location, length: selection.length),
      edit: edit)
  }

  func selectReplacement() throws {
    try wait(for: originalText)
    var range = CFRange(
      location: edit.replacementRange.location, length: edit.replacementRange.length)
    guard let selection = AXValueCreate(.cfRange, &range),
      AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, selection)
        == .success
    else { throw InjectionError("Could not select the client's transcription correction") }

    let deadline = ProcessInfo.processInfo.systemUptime + 0.75
    repeat {
      try checkFocus()
      var selected: CFTypeRef?
      let result = AXUIElementCopyAttributeValue(
        field, kAXSelectedTextRangeAttribute as CFString, &selected)
      if result == .success, let selected, CFGetTypeID(selected) == AXValueGetTypeID() {
        var actual = CFRange()
        if AXValueGetValue(selected as! AXValue, .cfRange, &actual),
          actual.location == range.location, actual.length == range.length
        {
          try wait(for: originalText)
          return
        }
      }
      guard result == .success || result == .cannotComplete else {
        throw InjectionError("The client's text selection became unavailable during transcription")
      }
      Thread.sleep(forTimeInterval: 0.001)
    } while ProcessInfo.processInfo.systemUptime < deadline
    throw InjectionError("The client did not acknowledge the transcription selection")
  }

  private func checkFocus() throws {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
      throw InjectionError("The captured application is no longer frontmost")
    }
    var focused: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused)
        == .success,
      let focused, CFEqual(focused, field)
    else {
      throw InjectionError("The client's focused text field changed during transcription")
    }
  }

  func waitForInsertion() throws {
    try wait(for: edit.afterInsertion, isInsertion: true)
  }

  private func wait(for expected: String, isInsertion: Bool = false) throws {
    let deadline = ProcessInfo.processInfo.systemUptime + 0.75
    repeat {
      guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
      else { throw InjectionError("The captured application is no longer frontmost") }
      var value: CFTypeRef?
      let result = AXUIElementCopyAttributeValue(field, kAXValueAttribute as CFString, &value)
      if result == .success, let actual = value as? String,
        isInsertion ? edit.acknowledgesInsertion(actual) : actual == expected
      {
        try checkFocus()
        return
      }
      guard result == .success || result == .cannotComplete
      else {
        throw InjectionError("The client's text field became unavailable during transcription")
      }
      Thread.sleep(forTimeInterval: 0.001)
    } while ProcessInfo.processInfo.systemUptime < deadline
    throw InjectionError("The client did not acknowledge the live transcription edit")
  }
}
