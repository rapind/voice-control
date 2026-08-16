import Foundation
import TOMLDecoder

struct CommandPhrases: Equatable {
  var focus: [String]
  var newChat: [String]
  var clearContext: [String]
  var compactContext: [String]
  var interruptSession: [String]
  var startSession: [String]
  var next: [String]
  var previous: [String]
  var focus1: [String]
  var focus2: [String]
  var focus3: [String]
  var focus4: [String]
  var focus5: [String]
  var focus6: [String]
  var focus7: [String]
  var focus8: [String]
  var focus9: [String]

  static let ghosttyDefaults = CommandPhrases(
    focus: ["focus ghost tee"],
    newChat: ["new chat"],
    clearContext: ["clear context"],
    compactContext: ["compact context"],
    interruptSession: ["quit session"],
    startSession: ["start session"],
    next: ["focus next"],
    previous: ["focus previous", "focus prev"],
    focus1: ["focus 1"],
    focus2: ["focus 2"],
    focus3: ["focus 3"],
    focus4: ["focus 4"],
    focus5: ["focus 5"],
    focus6: ["focus 6"],
    focus7: ["focus 7"],
    focus8: ["focus 8"],
    focus9: ["focus 9"]
  )

  static let chatGPTDefaults = CommandPhrases(
    focus: ["focus chat"],
    newChat: ["new chat"],
    clearContext: [],
    compactContext: [],
    interruptSession: [],
    startSession: [],
    next: [],
    previous: [],
    focus1: ["focus 1"],
    focus2: ["focus 2"],
    focus3: ["focus 3"],
    focus4: ["focus 4"],
    focus5: ["focus 5"],
    focus6: ["focus 6"],
    focus7: ["focus 7"],
    focus8: ["focus 8"],
    focus9: ["focus 9"]
  )

  static let chromeDefaults = CommandPhrases(
    focus: ["focus chrome"],
    newChat: [],
    clearContext: [],
    compactContext: [],
    interruptSession: [],
    startSession: [],
    next: [],
    previous: [],
    focus1: ["focus 1"],
    focus2: ["focus 2"],
    focus3: ["focus 3"],
    focus4: ["focus 4"],
    focus5: ["focus 5"],
    focus6: ["focus 6"],
    focus7: ["focus 7"],
    focus8: ["focus 8"],
    focus9: ["focus 9"]
  )

  var nonFocusMappings: [(ApplicationCommand, [String])] {
    [
      (.newChat, newChat),
      (.clearContext, clearContext),
      (.compactContext, compactContext),
      (.interruptSession, interruptSession),
      (.startSession, startSession),
      (.nextItem, next),
      (.previousItem, previous),
    ] + positionalMappings
  }

  var positionalMappings: [(ApplicationCommand, [String])] {
    [
      (.focusItem(1), focus1),
      (.focusItem(2), focus2),
      (.focusItem(3), focus3),
      (.focusItem(4), focus4),
      (.focusItem(5), focus5),
      (.focusItem(6), focus6),
      (.focusItem(7), focus7),
      (.focusItem(8), focus8),
      (.focusItem(9), focus9),
    ]
  }

}

struct Configuration: Equatable {
  var wakePhrases: [String]
  var submitPhrases: [String]
  var cancelPhrases: [String]
  var silenceSeconds: TimeInterval
  var silenceThresholdDB: Float
  var maximumRecordingSeconds: TimeInterval
  var applicationCommands: [ApplicationTarget: CommandPhrases]

  static let defaults = Configuration(
    wakePhrases: ["ghostee", "ghostty", "ghostie", "ghosty", "ghost tea"],
    submitPhrases: ["ghost it"],
    cancelPhrases: ["ghost cancel"],
    silenceSeconds: 4,
    silenceThresholdDB: -45,
    maximumRecordingSeconds: 90,
    applicationCommands: [
      .ghostty: .ghosttyDefaults,
      .chatGPT: .chatGPTDefaults,
      .chrome: .chromeDefaults,
    ]
  )

  static let defaultTOML = """
    # Voice Control reloads this file automatically after you save it.
    wake = ["ghostee", "ghostty", "ghostie", "ghosty", "ghost tea"]
    submit = ["ghost it"]
    cancel = ["ghost cancel"]

    silence_seconds = 4
    silence_threshold_db = -45
    maximum_recording_seconds = 90

    [applications.ghostty.commands]
    focus = ["focus ghost tee"]
    new_chat = ["new chat"]
    clear_context = ["clear context"]
    compact_context = ["compact context"]
    interrupt_session = ["quit session"]
    start_session = ["start session"]
    next = ["focus next"]
    previous = ["focus previous", "focus prev"]
    focus_1 = ["focus 1"]
    focus_2 = ["focus 2"]
    focus_3 = ["focus 3"]
    focus_4 = ["focus 4"]
    focus_5 = ["focus 5"]
    focus_6 = ["focus 6"]
    focus_7 = ["focus 7"]
    focus_8 = ["focus 8"]
    focus_9 = ["focus 9"]

    [applications.chatgpt.commands]
    focus = ["focus chat"]
    new_chat = ["new chat"]
    focus_1 = ["focus 1"]
    focus_2 = ["focus 2"]
    focus_3 = ["focus 3"]
    focus_4 = ["focus 4"]
    focus_5 = ["focus 5"]
    focus_6 = ["focus 6"]
    focus_7 = ["focus 7"]
    focus_8 = ["focus 8"]
    focus_9 = ["focus 9"]

    [applications.chrome.commands]
    focus = ["focus chrome"]
    focus_1 = ["focus 1"]
    focus_2 = ["focus 2"]
    focus_3 = ["focus 3"]
    focus_4 = ["focus 4"]
    focus_5 = ["focus 5"]
    focus_6 = ["focus 6"]
    focus_7 = ["focus 7"]
    focus_8 = ["focus 8"]
    focus_9 = ["focus 9"]
    """

  static var defaultFileURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/voice-control/config.toml")
  }

  var contextualPhrases: [String] {
    var seen: Set<String> = []
    let phrases =
      wakePhrases + submitPhrases + cancelPhrases
      + ApplicationTarget.allCases.flatMap { commandMappings(for: $0).flatMap(\.1) }
    return phrases.filter { seen.insert(PhraseMatcher.normalize($0)).inserted }
  }

  static func decodeTOML(_ data: Data) throws -> Configuration {
    let raw: RawConfiguration
    do {
      raw = try TOMLDecoder().decode(RawConfiguration.self, from: data)
    } catch {
      throw ConfigurationError("Invalid TOML: \(error.localizedDescription)")
    }
    guard raw.commands == nil else {
      throw ConfigurationError(
        "[commands] is invalid; put commands under an [applications.<name>.commands] table"
      )
    }

    let defaults = Configuration.defaults
    var configuration = Configuration(
      wakePhrases: raw.wake ?? defaults.wakePhrases,
      submitPhrases: raw.submit ?? defaults.submitPhrases,
      cancelPhrases: raw.cancel ?? defaults.cancelPhrases,
      silenceSeconds: raw.silenceSeconds ?? defaults.silenceSeconds,
      silenceThresholdDB: Float(raw.silenceThresholdDB ?? Double(defaults.silenceThresholdDB)),
      maximumRecordingSeconds: raw.maximumRecordingSeconds
        ?? defaults.maximumRecordingSeconds,
      applicationCommands: [
        .ghostty: commandPhrases(
          raw.applications?.ghostty?.commands,
          defaults: defaults.applicationCommands[.ghostty]!
        ),
        .chatGPT: commandPhrases(
          raw.applications?.chatGPT?.commands,
          defaults: defaults.applicationCommands[.chatGPT]!
        ),
        .chrome: commandPhrases(
          raw.applications?.chrome?.commands,
          defaults: defaults.applicationCommands[.chrome]!
        ),
      ]
    )
    try configuration.validateAndNormalize()
    return configuration
  }

  private static func commandPhrases(
    _ raw: RawCommandPhrases?, defaults: CommandPhrases
  ) -> CommandPhrases {
    CommandPhrases(
      focus: raw?.focus ?? defaults.focus,
      newChat: raw?.newChat ?? defaults.newChat,
      clearContext: raw?.clearContext ?? defaults.clearContext,
      compactContext: raw?.compactContext ?? defaults.compactContext,
      interruptSession: raw?.interruptSession ?? defaults.interruptSession,
      startSession: raw?.startSession ?? defaults.startSession,
      next: raw?.next ?? defaults.next,
      previous: raw?.previous ?? defaults.previous,
      focus1: raw?.focus1 ?? defaults.focus1,
      focus2: raw?.focus2 ?? defaults.focus2,
      focus3: raw?.focus3 ?? defaults.focus3,
      focus4: raw?.focus4 ?? defaults.focus4,
      focus5: raw?.focus5 ?? defaults.focus5,
      focus6: raw?.focus6 ?? defaults.focus6,
      focus7: raw?.focus7 ?? defaults.focus7,
      focus8: raw?.focus8 ?? defaults.focus8,
      focus9: raw?.focus9 ?? defaults.focus9
    )
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

    for target in ApplicationTarget.allCases {
      var commands = applicationCommands[target]!
      commands.focus = Self.normalizedPhrases(commands.focus)
      commands.newChat = Self.normalizedPhrases(commands.newChat)
      commands.clearContext = Self.normalizedPhrases(commands.clearContext)
      commands.compactContext = Self.normalizedPhrases(commands.compactContext)
      commands.interruptSession = Self.normalizedPhrases(commands.interruptSession)
      commands.startSession = Self.normalizedPhrases(commands.startSession)
      commands.next = Self.normalizedPhrases(commands.next)
      commands.previous = Self.normalizedPhrases(commands.previous)
      commands.focus1 = Self.normalizedPhrases(commands.focus1)
      commands.focus2 = Self.normalizedPhrases(commands.focus2)
      commands.focus3 = Self.normalizedPhrases(commands.focus3)
      commands.focus4 = Self.normalizedPhrases(commands.focus4)
      commands.focus5 = Self.normalizedPhrases(commands.focus5)
      commands.focus6 = Self.normalizedPhrases(commands.focus6)
      commands.focus7 = Self.normalizedPhrases(commands.focus7)
      commands.focus8 = Self.normalizedPhrases(commands.focus8)
      commands.focus9 = Self.normalizedPhrases(commands.focus9)
      applicationCommands[target] = commands
    }
    for target in [ApplicationTarget.chatGPT, .chrome] {
      let commands = applicationCommands[target]!
      guard
        commands.next.isEmpty,
        commands.previous.isEmpty,
        commands.clearContext.isEmpty,
        commands.compactContext.isEmpty,
        commands.interruptSession.isEmpty,
        commands.startSession.isEmpty
      else {
        throw ConfigurationError(
          "\(target.displayName) does not support context, session, next, or previous commands"
        )
      }
    }

    guard silenceSeconds >= 1 else {
      throw ConfigurationError("silence_seconds must be at least 1")
    }
    guard (-100...0).contains(silenceThresholdDB) else {
      throw ConfigurationError("silence_threshold_db must be between -100 and 0")
    }
    guard maximumRecordingSeconds >= 5 else {
      throw ConfigurationError("maximum_recording_seconds must be at least 5")
    }

    for target in ApplicationTarget.allCases {
      var owners: [String: String] = [:]
      let groups: [(String, [String])] =
        [
          ("wake", wakePhrases),
          ("submit", submitPhrases),
          ("cancel", cancelPhrases),
        ] + commandMappings(for: target).map { ("command \($0.0)", $0.1) }
      for (owner, phrases) in groups {
        for phrase in phrases {
          let normalized = PhraseMatcher.normalize(phrase)
          if let existingOwner = owners[normalized], existingOwner != owner {
            throw ConfigurationError(
              "Phrase \"\(phrase)\" is assigned to both \(existingOwner) and \(owner) for \(target.rawValue)"
            )
          }
          owners[normalized] = owner
        }
      }
    }
  }

  func commandMappings(for sessionTarget: ApplicationTarget?) -> [(
    ApplicationCommand, [String]
  )] {
    let globalFocusMappings: [(ApplicationCommand, [String])] = ApplicationTarget.allCases.map {
      target in
      (.focus(target), applicationCommands[target]!.focus)
    }
    guard let sessionTarget else {
      return globalFocusMappings
        + ApplicationTarget.allCases.flatMap { applicationCommands[$0]!.positionalMappings }
    }
    return globalFocusMappings + applicationCommands[sessionTarget]!.nonFocusMappings
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
  var target: ApplicationTarget?
  var wake: [String]?
  var submit: [String]?
  var cancel: [String]?
  var silenceSeconds: Double?
  var silenceThresholdDB: Double?
  var maximumRecordingSeconds: Double?
  var applications: RawApplications?
  var commands: RawCommandPhrases?

  enum CodingKeys: String, CodingKey {
    case target, wake, submit, cancel, applications, commands
    case silenceSeconds = "silence_seconds"
    case silenceThresholdDB = "silence_threshold_db"
    case maximumRecordingSeconds = "maximum_recording_seconds"
  }
}

private struct RawApplications: Decodable {
  var ghostty: RawApplication?
  var chatGPT: RawApplication?
  var chrome: RawApplication?

  enum CodingKeys: String, CodingKey {
    case ghostty
    case chatGPT = "chatgpt"
    case chrome
  }
}

private struct RawApplication: Decodable {
  var commands: RawCommandPhrases?
}

private struct RawCommandPhrases: Decodable {
  var focus: [String]?
  var newChat: [String]?
  var clearContext: [String]?
  var compactContext: [String]?
  var interruptSession: [String]?
  var startSession: [String]?
  var next: [String]?
  var previous: [String]?
  var focus1: [String]?
  var focus2: [String]?
  var focus3: [String]?
  var focus4: [String]?
  var focus5: [String]?
  var focus6: [String]?
  var focus7: [String]?
  var focus8: [String]?
  var focus9: [String]?

  enum CodingKeys: String, CodingKey {
    case focus, next, previous
    case newChat = "new_chat"
    case clearContext = "clear_context"
    case compactContext = "compact_context"
    case interruptSession = "interrupt_session"
    case startSession = "start_session"
    case focus1 = "focus_1"
    case focus2 = "focus_2"
    case focus3 = "focus_3"
    case focus4 = "focus_4"
    case focus5 = "focus_5"
    case focus6 = "focus_6"
    case focus7 = "focus_7"
    case focus8 = "focus_8"
    case focus9 = "focus_9"
  }
}

struct ConfigurationError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}
