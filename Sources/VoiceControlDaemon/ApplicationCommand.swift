import Foundation

enum ApplicationCommand: Equatable, Hashable {
  case focus(ApplicationTarget)
  case newChat
  case focusItem(Int)
  case nextItem
  case previousItem

  var focusTarget: ApplicationTarget? {
    if case .focus(let target) = self { return target }
    return nil
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
