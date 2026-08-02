import Foundation

enum ApplicationTarget: String, Decodable, Equatable, Hashable {
  case ghostty
  case chatGPT = "chatgpt"

  var displayName: String {
    switch self {
    case .ghostty: return "Ghostty"
    case .chatGPT: return "ChatGPT"
    }
  }

  var bundleIdentifiers: Set<String> {
    switch self {
    case .ghostty:
      return ["com.mitchellh.ghostty", "com.mitchellh.ghostty.debug"]
    case .chatGPT:
      return ["com.openai.codex"]
    }
  }
}
