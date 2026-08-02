import Foundation

enum GhosttyCommand: Equatable {
  case focus
  case newTab
  case focusTab(Int)
  case nextTab
  case previousTab

  static func parse(
    _ transcript: String,
    wakePhrases: [String],
    commands: CommandPhrases
  ) -> GhosttyCommand? {
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
