import Foundation

enum ApplicationCommand: Equatable, Hashable {
  case focus
  case newChat
  case focusItem(Int)
  case nextItem
  case previousItem

  static func parse(
    _ transcript: String,
    wakePhrases: [String],
    commands: CommandPhrases
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

    for (command, phrases) in commands.mappings {
      if phrases.contains(where: { PhraseMatcher.normalize($0) == normalized }) {
        return command
      }
    }
    return nil
  }
}
