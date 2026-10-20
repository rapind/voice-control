import AppKit
import ApplicationServices
import Foundation

struct PreviewFieldEdit: Equatable {
  let replacementRange: NSRange
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
    replacementRange = NSRange(
      location: prefix.utf16.count,
      length: selection.location + selection.length - prefix.utf16.count)
    afterDeletion = edit.deleteCount > 0 ? prefix + suffix : text
    afterInsertion = edit.insertion.isEmpty ? afterDeletion : prefix + edit.insertion + suffix
  }
}

// Corrections replace one acknowledged selection. Field values can include
// disappearing placeholders, so they are not used to acknowledge posted text.
struct EditablePreviewTarget {
  private let field: AXUIElement
  private let text: String
  private let selection: NSRange

  init(pid: pid_t) throws {
    let application = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(application, 0.1)
    var focused: CFTypeRef?
    var focusResult = AXUIElementCopyAttributeValue(
      application, kAXFocusedUIElementAttribute as CFString, &focused)
    if focusResult == .noValue {
      var enhanced: CFTypeRef?
      if AXUIElementCopyAttributeValue(
        application, "AXEnhancedUserInterface" as CFString, &enhanced) == .success,
        enhanced as? Bool == false
      {
        // Native clients can populate their focused field asynchronously after
        // Accessibility is enabled. The field query, not the setter status,
        // determines whether the correction's selection can be read.
        AXUIElementSetAttributeValue(
          application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        focused = nil
        focusResult = AXUIElementCopyAttributeValue(
          application, kAXFocusedUIElementAttribute as CFString, &focused)
      }
    }
    guard focusResult == .success, let focused,
      CFGetTypeID(focused) == AXUIElementGetTypeID()
    else {
      throw InjectionError(
        "Could not read the client's focused text field (AX \(focusResult.rawValue))")
    }
    field = focused as! AXUIElement
    AXUIElementSetMessagingTimeout(field, 0.1)
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
    self.text = text
    self.selection = NSRange(location: selection.location, length: selection.length)
  }

  func selectReplacement(for edit: PreviewEdit) throws {
    let replacement = try PreviewFieldEdit(text: text, selection: selection, edit: edit)
    var range = CFRange(
      location: replacement.replacementRange.location, length: replacement.replacementRange.length)
    guard let selection = AXValueCreate(.cfRange, &range),
      AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, selection)
        == .success
    else { throw InjectionError("Could not select the client's transcription correction") }

    let deadline = ProcessInfo.processInfo.systemUptime + 0.75
    repeat {
      var selected: CFTypeRef?
      let result = AXUIElementCopyAttributeValue(
        field, kAXSelectedTextRangeAttribute as CFString, &selected)
      if result == .success, let selected, CFGetTypeID(selected) == AXValueGetTypeID() {
        var actual = CFRange()
        if AXValueGetValue(selected as! AXValue, .cfRange, &actual),
          actual.location == range.location, actual.length == range.length
        {
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

}

protocol PreviewCorrectionTarget {
  func selectReplacement(for edit: PreviewEdit) throws
}

extension EditablePreviewTarget: PreviewCorrectionTarget {}

struct PendingPreviewCorrection {
  private var target: (any PreviewCorrectionTarget)?

  var isPending: Bool { target != nil }

  mutating func selectReplacement(
    for edit: PreviewEdit,
    makeTarget: () throws -> any PreviewCorrectionTarget
  ) throws {
    do {
      // Selection may have moved even when acknowledgement failed. Retain the
      // original field snapshot until text is posted, so retries do not delete twice.
      if target == nil { target = try makeTarget() }
      try target?.selectReplacement(for: edit)
    } catch {
      throw CorrectionSelectionError(underlyingError: error)
    }
  }
}
