import Foundation

enum ApplicationTarget: String, CaseIterable, Decodable, Equatable, Hashable {
  case ghostty
  case chatGPT = "chatgpt"
  case chrome

  init?(bundleIdentifier: String) {
    guard
      let target = Self.allCases.first(where: { $0.bundleIdentifiers.contains(bundleIdentifier) })
    else {
      return nil
    }
    self = target
  }

  var displayName: String {
    switch self {
    case .ghostty: return "Ghostty"
    case .chatGPT: return "ChatGPT"
    case .chrome: return "Google Chrome"
    }
  }

  var bundleIdentifiers: Set<String> {
    switch self {
    case .ghostty:
      return ["com.mitchellh.ghostty", "com.mitchellh.ghostty.debug"]
    case .chatGPT:
      return ["com.openai.codex"]
    case .chrome:
      return ["com.google.Chrome"]
    }
  }
}
