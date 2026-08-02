import Foundation

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
    submitPhrases: [String]
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
    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func strip(phrase: String, fromStartOf text: String) -> String {
    let escaped = NSRegularExpression.escapedPattern(for: phrase)
    let pattern = "^\\s*\(escaped)\\b[\\s,.:;!?-]*"
    return replace(pattern: pattern, in: text)
  }

  private static func strip(phrase: String, fromEndOf text: String) -> String {
    let escaped = NSRegularExpression.escapedPattern(for: phrase)
    let pattern = "[\\s,.:;!?-]*\\b\(escaped)[\\s,.:;!?-]*$"
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
