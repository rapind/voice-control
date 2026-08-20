import Foundation
import Testing

@Test func launchAgentSupervisesTheDaemonAndRestartsOnlyAfterFailure() throws {
  let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let templateURL = repositoryRoot.appendingPathComponent(
    "com.daverapin.voice-control-prototype.plist.template"
  )
  let data = try Data(contentsOf: templateURL)
  let propertyList = try #require(
    PropertyListSerialization.propertyList(from: data, format: nil)
      as? [String: Any]
  )
  let arguments = try #require(propertyList["ProgramArguments"] as? [String])
  let keepAlive = try #require(propertyList["KeepAlive"] as? [String: Bool])

  #expect(arguments.first == "__VOICE_CONTROL_EXECUTABLE__")
  #expect(arguments.first != "/usr/bin/open")
  #expect(propertyList["RunAtLoad"] as? Bool == true)
  #expect(keepAlive["SuccessfulExit"] == false)
}
