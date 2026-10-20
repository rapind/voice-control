import Foundation
import Testing

@testable import VoiceControlDaemon

@Test func correctionRetryKeepsItsOriginalSelectionAfterAnAcknowledgementFailure() throws {
  let field = UnacknowledgedCorrectionField(text: "We can apt today", caret: 10)
  var pending = PendingPreviewCorrection()
  var captures = 0
  let makeTarget = {
    captures += 1
    return field as any PreviewCorrectionTarget
  }

  #expect(throws: CorrectionSelectionError.self) {
    try pending.selectReplacement(
      for: PreviewEdit(deleteCount: 1, insertion: "ply it"), makeTarget: makeTarget)
  }
  #expect(pending.isPending)
  #expect(field.selectedRange == NSRange(location: 9, length: 1))

  try pending.selectReplacement(
    for: PreviewEdit(deleteCount: 3, insertion: "apply it now"), makeTarget: makeTarget)

  #expect(captures == 1)
  #expect(field.selectedRange == NSRange(location: 7, length: 3))
  #expect(field.replacement?.afterInsertion == "We can apply it now today")
}

@Test func pendingCorrectionRestoresTheOriginalCaretWhenRecognitionReturnsToAppending() throws {
  let field = UnacknowledgedCorrectionField(text: "We can apt", caret: 10)
  var pending = PendingPreviewCorrection()

  #expect(throws: CorrectionSelectionError.self) {
    try pending.selectReplacement(for: PreviewEdit(deleteCount: 3, insertion: "apply it")) {
      field
    }
  }

  try pending.selectReplacement(for: PreviewEdit(deleteCount: 0, insertion: " today")) {
    Issue.record("A pending correction must retain its original field snapshot")
    return field
  }

  #expect(field.selectedRange == NSRange(location: 10, length: 0))
  #expect(field.replacement?.afterInsertion == "We can apt today")
}

@Test func correctionCanRetryAfterTheFieldIsTemporarilyUnavailable() throws {
  var pending = PendingPreviewCorrection()
  #expect(throws: CorrectionSelectionError.self) {
    try pending.selectReplacement(for: PreviewEdit(deleteCount: 3, insertion: "apply it")) {
      throw InjectionError("Could not read the client's focused text field (AX -25212)")
    }
  }
  #expect(!pending.isPending)

  let field = UnacknowledgedCorrectionField(text: "We can apt", caret: 10)
  field.acknowledgementFailures = 0
  try pending.selectReplacement(for: PreviewEdit(deleteCount: 3, insertion: "apply it")) {
    field
  }
  #expect(field.replacement?.afterInsertion == "We can apply it")
}

private final class UnacknowledgedCorrectionField: PreviewCorrectionTarget {
  private let originalText: String
  private let originalSelection: NSRange
  var acknowledgementFailures = 1
  private(set) var selectedRange: NSRange
  private(set) var replacement: PreviewFieldEdit?

  init(text: String, caret: Int) {
    originalText = text
    originalSelection = NSRange(location: caret, length: 0)
    selectedRange = originalSelection
  }

  func selectReplacement(for edit: PreviewEdit) throws {
    let replacement = try PreviewFieldEdit(
      text: originalText, selection: originalSelection, edit: edit)
    selectedRange = replacement.replacementRange
    if acknowledgementFailures > 0 {
      acknowledgementFailures -= 1
      throw InjectionError("The client did not acknowledge the transcription selection")
    }
    self.replacement = replacement
  }
}
