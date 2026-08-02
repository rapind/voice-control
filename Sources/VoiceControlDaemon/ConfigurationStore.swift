import Foundation

final class ConfigurationStore {
  var onConfigurationChanged: ((Configuration) -> Void)?
  var onError: ((String) -> Void)?

  let fileURL: URL
  private(set) var configuration: Configuration
  private var lastData: Data
  private var timer: Timer?

  init(fileURL: URL) throws {
    self.fileURL = fileURL
    try Configuration.ensureDefaultFile(at: fileURL)
    let data = try Data(contentsOf: fileURL)
    self.configuration = try Configuration.decodeTOML(data)
    self.lastData = data
  }

  func startWatching() {
    timer?.invalidate()
    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      self?.reloadIfChanged()
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  func stopWatching() {
    timer?.invalidate()
    timer = nil
  }

  func reloadIfChanged() {
    do {
      let data = try Data(contentsOf: fileURL)
      guard data != lastData else { return }
      lastData = data
      let updated = try Configuration.decodeTOML(data)
      configuration = updated
      onConfigurationChanged?(updated)
    } catch {
      onError?("Could not reload \(fileURL.path): \(error.localizedDescription)")
    }
  }
}
