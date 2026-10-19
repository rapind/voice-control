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

@Test func previewAcknowledgesCodexRemovingItsEmptyParagraphOnFirstInsertion() throws {
  // Captured AX values: the empty composer contains a newline; typing removes it.
  let change = try PreviewFieldEdit(
    text: "\n", selection: NSRange(location: 0, length: 0),
    edit: PreviewEdit(deleteCount: 0, insertion: "The blue folder."))
  #expect(change.acknowledgesInsertion("The blue folder."))
  #expect(change.acknowledgesInsertion("The blue folder.\n"))
  #expect(!change.acknowledgesInsertion("The blue"))
  #expect(!change.acknowledgesInsertion("The blue folder. "))
}

@Test func previewAcknowledgementStillRequiresExistingTextAndInsertedNewlines() throws {
  let existingText = try PreviewFieldEdit(
    text: "Keep this\n", selection: NSRange(location: 0, length: 0),
    edit: PreviewEdit(deleteCount: 0, insertion: "New words. "))
  #expect(existingText.acknowledgesInsertion("New words. Keep this\n"))
  #expect(!existingText.acknowledgesInsertion("New words."))
  #expect(!existingText.acknowledgesInsertion("New words. Keep this"))

  let insertedNewline = try PreviewFieldEdit(
    text: "", selection: NSRange(location: 0, length: 0),
    edit: PreviewEdit(deleteCount: 0, insertion: "New words.\n"))
  #expect(!insertedNewline.acknowledgesInsertion("New words."))

  let selectedNewline = try PreviewFieldEdit(
    text: "\n", selection: NSRange(location: 0, length: 1),
    edit: PreviewEdit(deleteCount: 0, insertion: "New words."))
  #expect(selectedNewline.acknowledgesInsertion("New words."))
  #expect(!selectedNewline.acknowledgesInsertion("New words.\n"))
}

@Test func previewAcknowledgementDoesNotTreatMultipleBlankLinesAsAnEmptyParagraph() throws {
  let change = try PreviewFieldEdit(
    text: "\n\n", selection: NSRange(location: 0, length: 0),
    edit: PreviewEdit(deleteCount: 0, insertion: "The blue folder."))
  #expect(change.acknowledgesInsertion("The blue folder.\n\n"))
  #expect(!change.acknowledgesInsertion("The blue folder."))
  #expect(!change.acknowledgesInsertion("The blue folder.\n"))

  let caretAfterNewline = try PreviewFieldEdit(
    text: "\n", selection: NSRange(location: 1, length: 0),
    edit: PreviewEdit(deleteCount: 0, insertion: "New words."))
  #expect(caretAfterNewline.acknowledgesInsertion("\nNew words."))
  #expect(!caretAfterNewline.acknowledgesInsertion("New words."))
}
