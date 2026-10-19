import Foundation
import Testing

@testable import VoiceControlDaemon

@Test func previewReplacementPreservesTextAfterTheCaret() throws {
  let change = try PreviewFieldEdit(
    text: "We can app today", selection: NSRange(location: 10, length: 0),
    edit: PreviewEdit(deleteCount: 3, insertion: "apply it"))
  #expect(change.replacementRange == NSRange(location: 7, length: 3))
  #expect(change.afterDeletion == "We can  today")
  #expect(change.afterInsertion == "We can apply it today")
}

@Test func previewInsertionReplacesAnExistingSelection() throws {
  let change = try PreviewFieldEdit(
    text: "We can wait today", selection: NSRange(location: 7, length: 4),
    edit: PreviewEdit(deleteCount: 0, insertion: "apply it"))
  #expect(change.replacementRange == NSRange(location: 7, length: 4))
  #expect(change.afterDeletion == "We can wait today")
  #expect(change.afterInsertion == "We can apply it today")
}

@Test func previewBackspaceDeletesSelectionBeforePrecedingCharacters() throws {
  let change = try PreviewFieldEdit(
    text: "We can wait today", selection: NSRange(location: 7, length: 4),
    edit: PreviewEdit(deleteCount: 2, insertion: " apply it"))
  #expect(change.replacementRange == NSRange(location: 6, length: 5))
  #expect(change.afterDeletion == "We can today")
  #expect(change.afterInsertion == "We can apply it today")
}

@Test func previewDeletionCountsGraphemesAndSelectionUsesUTF16() throws {
  let text = "Café 👩🏽‍💻 e\u{301}"
  let change = try PreviewFieldEdit(
    text: text, selection: NSRange(location: text.utf16.count, length: 0),
    edit: PreviewEdit(deleteCount: 3, insertion: ""))
  #expect(change.replacementRange == NSRange(location: 5, length: text.utf16.count - 5))
  #expect(change.afterDeletion == "Café ")
  #expect(change.afterInsertion == "Café ")
}

@Test func previewBackspaceAtTheStartDoesNotRemoveFollowingText() throws {
  let change = try PreviewFieldEdit(
    text: "suffix", selection: NSRange(location: 0, length: 0),
    edit: PreviewEdit(deleteCount: 5, insertion: "prefix "))
  #expect(change.replacementRange == NSRange(location: 0, length: 0))
  #expect(change.afterDeletion == "suffix")
  #expect(change.afterInsertion == "prefix suffix")
}

@Test func previewRejectsInvalidSelectionsBeforePostingKeys() {
  for selection in [
    NSRange(location: 4, length: 0), NSRange(location: 0, length: 4),
    NSRange(location: 1, length: 0),
  ] {
    #expect(throws: InjectionError.self) {
      try PreviewFieldEdit(
        text: "😀", selection: selection, edit: PreviewEdit(deleteCount: 0, insertion: "x"))
    }
  }
  #expect(throws: InjectionError.self) {
    try PreviewFieldEdit(
      text: "", selection: NSRange(location: 0, length: 0),
      edit: PreviewEdit(deleteCount: -1, insertion: ""))
  }
}
