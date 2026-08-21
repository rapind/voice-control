import Foundation

struct KeywordTranscript: Equatable {
  struct Segment: Equatable {
    let text: String
    let timestamp: TimeInterval
    let duration: TimeInterval
  }

  let text: String
  let segments: [Segment]
}

struct ControlPhraseMatch: Equatable {
  let phrase: String
  let startTime: TimeInterval
  let endTime: TimeInterval
  let transcriptEndTime: TimeInterval
}

enum PhraseMatcher {
  static func normalize(_ text: String) -> String {
    text.lowercased()
      .components(separatedBy: .punctuationCharacters)
      .joined(separator: " ")
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
  }

  static func contains(_ phrase: String, in text: String) -> Bool {
    let normalizedPhrase = normalize(phrase)
    var normalizedText = normalize(text)
    guard !normalizedPhrase.isEmpty else { return false }

    if normalizedPhrase.split(separator: " ").contains("codex") {
      normalizedText = canonicalizeCodex(in: normalizedText)
    }
    if normalizedPhrase.split(separator: " ").contains("ghostee") {
      normalizedText = canonicalizeGhostee(in: normalizedText)
    }

    let pattern = "(?:^|\\s)\(NSRegularExpression.escapedPattern(for: normalizedPhrase))(?:$|\\s)"
    return normalizedText.range(of: pattern, options: .regularExpression) != nil
  }

  static func contains(any phrases: [String], in text: String) -> Bool {
    phrases.contains { contains($0, in: text) }
  }

  static func trailingMatch(
    any phrases: [String],
    in transcript: KeywordTranscript,
    maximumTrailingWords: Int
  ) -> ControlPhraseMatch? {
    struct TimedWord {
      let text: String
      let timestamp: TimeInterval
      let duration: TimeInterval
    }

    guard maximumTrailingWords >= 0 else { return nil }
    let transcriptEndTime =
      transcript.segments.map { $0.timestamp + $0.duration }.max() ?? 0
    let words = transcript.segments.flatMap { segment in
      normalize(segment.text).split(separator: " ").map {
        TimedWord(
          text: String($0),
          timestamp: segment.timestamp,
          duration: segment.duration
        )
      }
    }
    var best: (startIndex: Int, wordCount: Int, match: ControlPhraseMatch)?

    for phrase in phrases {
      let phraseWords = normalize(phrase).split(separator: " ").map(String.init)
      guard !phraseWords.isEmpty, phraseWords.count <= words.count else { continue }

      for startIndex in stride(
        from: words.count - phraseWords.count,
        through: 0,
        by: -1
      ) {
        let endIndex = startIndex + phraseWords.count
        guard words.count - endIndex <= maximumTrailingWords else { continue }
        guard
          zip(words[startIndex..<endIndex], phraseWords).allSatisfy({
            $0.text == $1
          })
        else {
          continue
        }

        let first = words[startIndex]
        let last = words[endIndex - 1]
        let match = ControlPhraseMatch(
          phrase: phrase,
          startTime: first.timestamp,
          endTime: last.timestamp + last.duration,
          transcriptEndTime: transcriptEndTime
        )
        if best == nil
          || startIndex > best!.startIndex
          || (startIndex == best!.startIndex && phraseWords.count > best!.wordCount)
        {
          best = (startIndex, phraseWords.count, match)
        }
        break
      }
    }

    return best?.match
  }

  private static func canonicalizeCodex(in text: String) -> String {
    let aliases = ["code x", "kodex", "codec", "kodak"]
    return aliases.reduce(text) { current, alias in
      let escaped = NSRegularExpression.escapedPattern(for: alias)
      let pattern = "(?:^|\\s)\(escaped)(?=$|\\s)"
      guard let expression = try? NSRegularExpression(pattern: pattern) else { return current }
      let range = NSRange(current.startIndex..., in: current)
      return expression.stringByReplacingMatches(
        in: current,
        range: range,
        withTemplate: " codex"
      ).trimmingCharacters(in: .whitespaces)
    }
  }

  private static func canonicalizeGhostee(in text: String) -> String {
    let aliases = ["ghost tea", "ghostty", "ghostie", "ghosty"]
    return aliases.reduce(text) { current, alias in
      let escaped = NSRegularExpression.escapedPattern(for: alias)
      let pattern = "(?:^|\\s)\(escaped)(?=$|\\s)"
      guard let expression = try? NSRegularExpression(pattern: pattern) else { return current }
      let range = NSRange(current.startIndex..., in: current)
      return expression.stringByReplacingMatches(
        in: current,
        range: range,
        withTemplate: " ghostee"
      ).trimmingCharacters(in: .whitespaces)
    }
  }

  static func cleanFinalTranscript(
    _ text: String,
    wakePhrases: [String],
    submitPhrases: [String],
    explicitSubmitDetected: Bool = false
  )
    -> String
  {
    var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    for phrase in wakePhrases.sorted(by: { $0.count > $1.count }) {
      cleaned = strip(phrase: phrase, fromStartOf: cleaned)
    }
    for phrase in submitPhrases.sorted(by: { $0.count > $1.count }) {
      cleaned = strip(phrase: phrase, fromEndOf: cleaned)
    }
    if explicitSubmitDetected {
      for phrase in submitPhrases {
        let words = phrase.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count > 1 else { continue }
        for prefixLength in stride(from: words.count - 1, through: 1, by: -1) {
          cleaned = strip(
            phrase: words.prefix(prefixLength).joined(separator: " "),
            fromEndOf: cleaned
          )
        }
      }
    }
    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func strip(phrase: String, fromStartOf text: String) -> String {
    let escaped = NSRegularExpression.escapedPattern(for: phrase)
    let pattern = "^\\s*\(escaped)\\b[\\s,.:;!?-]*"
    return replace(pattern: pattern, in: text)
  }

  private static func strip(phrase: String, fromEndOf text: String) -> String {
    let escaped = NSRegularExpression.escapedPattern(for: phrase)
    let pattern = "\\s*\\b\(escaped)[\\s,.:;!?-]*$"
    return replace(pattern: pattern, in: text)
  }

  private static func replace(pattern: String, in text: String) -> String {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    else {
      return text
    }
    let range = NSRange(text.startIndex..., in: text)
    return expression.stringByReplacingMatches(in: text, range: range, withTemplate: "")
  }
}
