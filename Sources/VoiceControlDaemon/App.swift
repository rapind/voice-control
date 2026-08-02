import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let configurationStore: ConfigurationStore
  private var controller: VoiceController?
  private var statusItem: NSStatusItem?
  private let stateMenuItem = NSMenuItem(title: "Starting", action: nil, keyEquivalent: "")
  private let wakeMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
  private let targetMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
  private let submitMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
  private let cancelMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
  private let configStatusMenuItem = NSMenuItem(
    title: "Config: loaded", action: nil, keyEquivalent: "")

  init(configurationStore: ConfigurationStore) {
    self.configurationStore = configurationStore
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let configuration = configurationStore.configuration
    installStatusItem(configuration: configuration)
    let controller = VoiceController(configuration: configuration)
    controller.onStateChanged = { [weak self] phase in
      self?.updateStatus(phase)
    }
    controller.onConfigurationChanged = { [weak self] configuration in
      self?.updateConfigurationMenu(configuration)
      self?.configStatusMenuItem.title = "Config: reloaded"
    }
    configurationStore.onConfigurationChanged = { [weak controller, weak self] configuration in
      self?.configStatusMenuItem.title = "Config: applying…"
      controller?.updateConfiguration(configuration)
    }
    configurationStore.onError = { [weak self] message in
      self?.configStatusMenuItem.title = "Config error: \(message)"
      NSSound.beep()
      print("CONFIG ERROR: \(message)")
    }
    self.controller = controller
    controller.start()
    configurationStore.startWatching()
  }

  func applicationWillTerminate(_ notification: Notification) {
    configurationStore.stopWatching()
    controller?.stop()
  }

  @objc private func openConfiguration() {
    NSWorkspace.shared.open(configurationStore.fileURL)
  }

  @objc private func quit() {
    NSApplication.shared.terminate(nil)
  }

  private func installStatusItem(configuration: Configuration) {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.title = "VC …"
    let menu = NSMenu()
    stateMenuItem.isEnabled = false
    wakeMenuItem.isEnabled = false
    targetMenuItem.isEnabled = false
    submitMenuItem.isEnabled = false
    cancelMenuItem.isEnabled = false
    configStatusMenuItem.isEnabled = false
    menu.addItem(stateMenuItem)
    menu.addItem(targetMenuItem)
    menu.addItem(wakeMenuItem)
    menu.addItem(submitMenuItem)
    menu.addItem(cancelMenuItem)
    menu.addItem(configStatusMenuItem)
    menu.addItem(.separator())
    let openConfigItem = NSMenuItem(
      title: "Open Configuration", action: #selector(openConfiguration), keyEquivalent: ",")
    openConfigItem.target = self
    menu.addItem(openConfigItem)
    let quitItem = NSMenuItem(
      title: "Quit Voice Control", action: #selector(quit), keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)
    item.menu = menu
    statusItem = item
    updateConfigurationMenu(configuration)
  }

  private func updateConfigurationMenu(_ configuration: Configuration) {
    targetMenuItem.title = "Target: \(configuration.target.displayName)"
    wakeMenuItem.title = "Wake: \(configuration.wakePhrases.joined(separator: ", "))"
    submitMenuItem.title = "Submit: \(configuration.submitPhrases.joined(separator: ", "))"
    cancelMenuItem.title = "Cancel: \(configuration.cancelPhrases.joined(separator: ", "))"
  }

  private func updateStatus(_ phase: VoicePhase) {
    stateMenuItem.title = phase.description
    switch phase {
    case .starting:
      statusItem?.button?.title = "VC …"
    case .waitingForWake:
      statusItem?.button?.title = "VC idle"
    case .recording:
      statusItem?.button?.title = "VC REC"
    case .transcribing:
      statusItem?.button?.title = "VC text"
    case .injecting:
      statusItem?.button?.title = "VC send"
    case .failed:
      statusItem?.button?.title = "VC !"
    }
  }
}

@main
enum VoiceControlApplication {
  static func main() {
    let configurationStore: ConfigurationStore
    do {
      let fileURL = try Configuration.fileURL(from: CommandLine.arguments)
      configurationStore = try ConfigurationStore(fileURL: fileURL)
    } catch {
      fputs("Configuration error: \(error.localizedDescription)\n", stderr)
      fputs("\(Configuration.help)\n", stderr)
      exit(2)
    }

    let application = NSApplication.shared
    let delegate = AppDelegate(configurationStore: configurationStore)
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
  }
}
