import Foundation

enum ApplicationCommand: Equatable, Hashable {
  case focus(ApplicationTarget)
  case newChat
  case clearContext
  case compactContext
  case interruptSession
  case startSession
  case shareSession
  case focusItem(Int)

  var focusTarget: ApplicationTarget? {
    if case .focus(let target) = self { return target }
    return nil
  }

  var isDirectFocusCommand: Bool {
    guard case .focusItem(let number) = self else { return false }
    return (1...8).contains(number)
  }

  func target(frontmost: ApplicationTarget?) -> ApplicationTarget? {
    focusTarget ?? frontmost
  }

  static func parse(
    _ transcript: String,
    wakePhrases: [String],
    mappings: [(ApplicationCommand, [String])]
  ) -> ApplicationCommand? {
    var normalized = PhraseMatcher.normalize(transcript)
    for phrase in wakePhrases.sorted(by: {
      PhraseMatcher.normalize($0).count > PhraseMatcher.normalize($1).count
    }) {
      let normalizedWake = PhraseMatcher.normalize(phrase)
      if normalized == normalizedWake {
        return nil
      }
      if normalized.hasPrefix("\(normalizedWake) ") {
        normalized.removeFirst(normalizedWake.count + 1)
        break
      }
    }

    for (command, phrases) in mappings {
      if phrases.contains(where: { PhraseMatcher.normalize($0) == normalized }) {
        return command
      }
    }
    return nil
  }
}
