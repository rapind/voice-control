import Testing

@testable import VoiceControlDaemon

@Test func audioTapWaitsForMatchingHardwareAndClientFormats() {
  #expect(
    AudioFormatReadiness.canInstallTap(
      hardwareSampleRate: 24_000,
      hardwareChannelCount: 1,
      clientSampleRate: 48_000,
      clientChannelCount: 1
    ) == false
  )
  #expect(
    AudioFormatReadiness.canInstallTap(
      hardwareSampleRate: 24_000,
      hardwareChannelCount: 1,
      clientSampleRate: 24_000,
      clientChannelCount: 1
    )
  )
}
