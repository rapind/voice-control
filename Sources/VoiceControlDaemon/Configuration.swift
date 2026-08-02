import Foundation
import TOMLDecoder

struct CommandPhrases: Equatable {
  var focus: [String]
  var newTab: [String]
  var nextTab: [String]
  var previousTab: [String]
  var focusTab1: [String]
  var focusTab2: [String]
  var focusTab3: [String]
  var focusTab4: [String]
  var focusTab5: [String]
  var focusTab6: [String]
  var focusTab7: [String]
  var focusTab8: [String]
  var focusTab9: [String]

  static let defaults = CommandPhrases(
    focus: ["focus ghostty", "focus ghostee", "show ghostty", "show ghostee"],
    newTab: ["new tab", "open new tab"],
    nextTab: ["next tab"],
    previousTab: ["previous tab", "prev tab"],
    focusTab1: ["focus tab 1", "tab 1"],
    focusTab2: ["focus tab 2", "tab 2"],
    focusTab3: ["focus tab 3", "tab 3"],
    focusTab4: ["focus tab 4", "tab 4"],
    focusTab5: ["focus tab 5", "tab 5"],
    focusTab6: ["focus tab 6", "tab 6"],
    focusTab7: ["focus tab 7", "tab 7"],
    focusTab8: ["focus tab 8", "tab 8"],
    focusTab9: ["focus tab 9", "tab 9"]
  )

  var mappings: [(GhosttyCommand, [String])] {
    [
      (.focus, focus),
      (.newTab, newTab),
      (.nextTab, nextTab),
      (.previousTab, previousTab),
      (.focusTab(1), focusTab1),
      (.focusTab(2), focusTab2),
      (.focusTab(3), focusTab3),
      (.focusTab(4), focusTab4),
      (.focusTab(5), focusTab5),
      (.focusTab(6), focusTab6),
      (.focusTab(7), focusTab7),
      (.focusTab(8), focusTab8),
      (.focusTab(9), focusTab9),
    ]
  }

  var allPhrases: [String] {
    mappings.flatMap(\.1)
  }
}

struct Configuration: Equatable {
  var wakePhrases: [String]
  var submitPhrases: [String]
  var cancelPhrases: [String]
  var silenceSeconds: TimeInterval
  var silenceThresholdDB: Float
  var maximumRecordingSeconds: TimeInterval
  var commands: CommandPhrases

  static let defaults = Configuration(
    wakePhrases: ["ghostee", "ghostty", "ghostie", "ghosty", "ghost tea"],
    submitPhrases: ["ghost it"],
    cancelPhrases: ["ghost cancel"],
    silenceSeconds: 4,
    silenceThresholdDB: -42,
    maximumRecordingSeconds: 90,
    commands: .defaults
  )

  static let defaultTOML = """
    # Voice Control reloads this file automatically after you save it.
    wake = ["ghostee", "ghostty", "ghostie", "ghosty", "ghost tea"]
    submit = ["ghost it"]
    cancel = ["ghost cancel"]

    silence_seconds = 4
    silence_threshold_db = -42
    maximum_recording_seconds = 90

    [commands]
    focus = ["focus ghostty", "focus ghostee", "show ghostty", "show ghostee"]
    new_tab = ["new tab", "open new tab"]
    next_tab = ["next tab"]
    previous_tab = ["previous tab", "prev tab"]
    focus_tab_1 = ["focus tab 1", "tab 1"]
    focus_tab_2 = ["focus tab 2", "tab 2"]
    focus_tab_3 = ["focus tab 3", "tab 3"]
    focus_tab_4 = ["focus tab 4", "tab 4"]
    focus_tab_5 = ["focus tab 5", "tab 5"]
    focus_tab_6 = ["focus tab 6", "tab 6"]
    focus_tab_7 = ["focus tab 7", "tab 7"]
    focus_tab_8 = ["focus tab 8", "tab 8"]
    focus_tab_9 = ["focus tab 9", "tab 9"]
    """

  static var defaultFileURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/voice-control/config.toml")
  }

  var contextualPhrases: [String] {
    wakePhrases + submitPhrases + cancelPhrases + commands.allPhrases
  }

  static func decodeTOML(_ data: Data) throws -> Configuration {
    let raw: RawConfiguration
    do {
      raw = try TOMLDecoder().decode(RawConfiguration.self, from: data)
    } catch {
      throw ConfigurationError("Invalid TOML: \(error.localizedDescription)")
    }

    let defaults = Configuration.defaults
    let commandDefaults = defaults.commands
    let rawCommands = raw.commands
    var configuration = Configuration(
      wakePhrases: raw.wake ?? defaults.wakePhrases,
      submitPhrases: raw.submit ?? defaults.submitPhrases,
      cancelPhrases: raw.cancel ?? defaults.cancelPhrases,
      silenceSeconds: raw.silenceSeconds ?? defaults.silenceSeconds,
      silenceThresholdDB: Float(raw.silenceThresholdDB ?? Double(defaults.silenceThresholdDB)),
      maximumRecordingSeconds: raw.maximumRecordingSeconds
        ?? defaults.maximumRecordingSeconds,
      commands: CommandPhrases(
        focus: rawCommands?.focus ?? commandDefaults.focus,
        newTab: rawCommands?.newTab ?? commandDefaults.newTab,
        nextTab: rawCommands?.nextTab ?? commandDefaults.nextTab,
        previousTab: rawCommands?.previousTab ?? commandDefaults.previousTab,
        focusTab1: rawCommands?.focusTab1 ?? commandDefaults.focusTab1,
        focusTab2: rawCommands?.focusTab2 ?? commandDefaults.focusTab2,
        focusTab3: rawCommands?.focusTab3 ?? commandDefaults.focusTab3,
        focusTab4: rawCommands?.focusTab4 ?? commandDefaults.focusTab4,
        focusTab5: rawCommands?.focusTab5 ?? commandDefaults.focusTab5,
        focusTab6: rawCommands?.focusTab6 ?? commandDefaults.focusTab6,
        focusTab7: rawCommands?.focusTab7 ?? commandDefaults.focusTab7,
        focusTab8: rawCommands?.focusTab8 ?? commandDefaults.focusTab8,
        focusTab9: rawCommands?.focusTab9 ?? commandDefaults.focusTab9
      )
    )
    try configuration.validateAndNormalize()
    return configuration
  }

  static func ensureDefaultFile(at url: URL) throws {
    guard !FileManager.default.fileExists(atPath: url.path) else { return }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(defaultTOML.utf8).write(to: url, options: .atomic)
  }

  static func fileURL(from arguments: [String]) throws -> URL {
    var index = 1
    var url = defaultFileURL
    while index < arguments.count {
      switch arguments[index] {
      case "--config":
        guard index + 1 < arguments.count else {
          throw ConfigurationError("Missing path after --config")
        }
        index += 1
        url = URL(fileURLWithPath: NSString(string: arguments[index]).expandingTildeInPath)
      case "--help", "-h":
        print(help)
        exit(0)
      default:
        throw ConfigurationError("Unknown argument: \(arguments[index])")
      }
      index += 1
    }
    return url.standardizedFileURL
  }

  static let help = """
    Voice Control Prototype

      --config PATH  TOML configuration file (default: ~/.config/voice-control/config.toml)
    """

  private mutating func validateAndNormalize() throws {
    wakePhrases = try Self.controlPhrases(wakePhrases, name: "wake")
    submitPhrases = try Self.controlPhrases(submitPhrases, name: "submit")
    cancelPhrases = try Self.controlPhrases(cancelPhrases, name: "cancel")

    commands.focus = Self.normalizedPhrases(commands.focus)
    commands.newTab = Self.normalizedPhrases(commands.newTab)
    commands.nextTab = Self.normalizedPhrases(commands.nextTab)
    commands.previousTab = Self.normalizedPhrases(commands.previousTab)
    commands.focusTab1 = Self.normalizedPhrases(commands.focusTab1)
    commands.focusTab2 = Self.normalizedPhrases(commands.focusTab2)
    commands.focusTab3 = Self.normalizedPhrases(commands.focusTab3)
    commands.focusTab4 = Self.normalizedPhrases(commands.focusTab4)
    commands.focusTab5 = Self.normalizedPhrases(commands.focusTab5)
    commands.focusTab6 = Self.normalizedPhrases(commands.focusTab6)
    commands.focusTab7 = Self.normalizedPhrases(commands.focusTab7)
    commands.focusTab8 = Self.normalizedPhrases(commands.focusTab8)
    commands.focusTab9 = Self.normalizedPhrases(commands.focusTab9)

    guard silenceSeconds >= 1 else {
      throw ConfigurationError("silence_seconds must be at least 1")
    }
    guard (-100...0).contains(silenceThresholdDB) else {
      throw ConfigurationError("silence_threshold_db must be between -100 and 0")
    }
    guard maximumRecordingSeconds >= 5 else {
      throw ConfigurationError("maximum_recording_seconds must be at least 5")
    }

    var owners: [String: String] = [:]
    let groups: [(String, [String])] =
      [
        ("wake", wakePhrases),
        ("submit", submitPhrases),
        ("cancel", cancelPhrases),
      ] + commands.mappings.map { ("command \($0.0)", $0.1) }
    for (owner, phrases) in groups {
      for phrase in phrases {
        let normalized = PhraseMatcher.normalize(phrase)
        if let existingOwner = owners[normalized], existingOwner != owner {
          throw ConfigurationError(
            "Phrase \"\(phrase)\" is assigned to both \(existingOwner) and \(owner)"
          )
        }
        owners[normalized] = owner
      }
    }
  }

  private static func controlPhrases(_ phrases: [String], name: String) throws -> [String] {
    let normalized = normalizedPhrases(phrases)
    guard !normalized.isEmpty else {
      throw ConfigurationError("\(name) must contain at least one phrase")
    }
    return normalized
  }

  private static func normalizedPhrases(_ phrases: [String]) -> [String] {
    var seen: Set<String> = []
    return phrases.compactMap { phrase in
      let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
      let normalized = PhraseMatcher.normalize(trimmed)
      guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
      return trimmed
    }
  }
}

private struct RawConfiguration: Decodable {
  var wake: [String]?
  var submit: [String]?
  var cancel: [String]?
  var silenceSeconds: Double?
  var silenceThresholdDB: Double?
  var maximumRecordingSeconds: Double?
  var commands: RawCommandPhrases?

  enum CodingKeys: String, CodingKey {
    case wake, submit, cancel, commands
    case silenceSeconds = "silence_seconds"
    case silenceThresholdDB = "silence_threshold_db"
    case maximumRecordingSeconds = "maximum_recording_seconds"
  }
}

private struct RawCommandPhrases: Decodable {
  var focus: [String]?
  var newTab: [String]?
  var nextTab: [String]?
  var previousTab: [String]?
  var focusTab1: [String]?
  var focusTab2: [String]?
  var focusTab3: [String]?
  var focusTab4: [String]?
  var focusTab5: [String]?
  var focusTab6: [String]?
  var focusTab7: [String]?
  var focusTab8: [String]?
  var focusTab9: [String]?

  enum CodingKeys: String, CodingKey {
    case focus
    case newTab = "new_tab"
    case nextTab = "next_tab"
    case previousTab = "previous_tab"
    case focusTab1 = "focus_tab_1"
    case focusTab2 = "focus_tab_2"
    case focusTab3 = "focus_tab_3"
    case focusTab4 = "focus_tab_4"
    case focusTab5 = "focus_tab_5"
    case focusTab6 = "focus_tab_6"
    case focusTab7 = "focus_tab_7"
    case focusTab8 = "focus_tab_8"
    case focusTab9 = "focus_tab_9"
  }
}

struct ConfigurationError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}
