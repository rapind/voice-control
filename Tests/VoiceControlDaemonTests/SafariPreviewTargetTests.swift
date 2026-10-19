import Foundation
import Testing

@testable import VoiceControlDaemon

@Test func safariAndDockWebAppsRequirePreviewAcknowledgement() {
  #expect(SafariPreviewTarget.requiresAcknowledgement(bundleIdentifier: "com.apple.Safari"))
  #expect(
    SafariPreviewTarget.requiresAcknowledgement(
      bundleIdentifier: "com.apple.SafariTechnologyPreview"))
  #expect(
    SafariPreviewTarget.requiresAcknowledgement(
      bundleIdentifier: "com.apple.Safari.WebApp.414BA5B6-E39D-489F-9A9C-B78F7EB31255"))
  #expect(!SafariPreviewTarget.requiresAcknowledgement(bundleIdentifier: "com.google.Chrome"))
  #expect(!SafariPreviewTarget.requiresAcknowledgement(bundleIdentifier: "com.mitchellh.ghostty"))
  #expect(!SafariPreviewTarget.requiresAcknowledgement(bundleIdentifier: nil))
}

@Test func previewReplacementPreservesTextAfterTheCaret() throws {
  let change = try PreviewFieldEdit(
    text: "We can app today", selection: NSRange(location: 10, length: 0),
    edit: PreviewEdit(deleteCount: 3, insertion: "apply it"))
  #expect(change.afterDeletion == "We can  today")
  #expect(change.afterInsertion == "We can apply it today")
}

@Test func previewInsertionReplacesAnExistingSelection() throws {
  let change = try PreviewFieldEdit(
    text: "We can wait today", selection: NSRange(location: 7, length: 4),
    edit: PreviewEdit(deleteCount: 0, insertion: "apply it"))
  #expect(change.afterDeletion == "We can wait today")
  #expect(change.afterInsertion == "We can apply it today")
}

@Test func previewBackspaceDeletesSelectionBeforePrecedingCharacters() throws {
  let change = try PreviewFieldEdit(
    text: "We can wait today", selection: NSRange(location: 7, length: 4),
    edit: PreviewEdit(deleteCount: 2, insertion: " apply it"))
  #expect(change.afterDeletion == "We can today")
  #expect(change.afterInsertion == "We can apply it today")
}

@Test func previewDeletionCountsGraphemesAndSelectionUsesUTF16() throws {
  let text = "Café 👩🏽‍💻 e\u{301}"
  let change = try PreviewFieldEdit(
    text: text, selection: NSRange(location: text.utf16.count, length: 0),
    edit: PreviewEdit(deleteCount: 3, insertion: ""))
  #expect(change.afterDeletion == "Café ")
  #expect(change.afterInsertion == "Café ")
}

@Test func previewBackspaceAtTheStartDoesNotRemoveFollowingText() throws {
  let change = try PreviewFieldEdit(
    text: "suffix", selection: NSRange(location: 0, length: 0),
    edit: PreviewEdit(deleteCount: 5, insertion: "prefix "))
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
