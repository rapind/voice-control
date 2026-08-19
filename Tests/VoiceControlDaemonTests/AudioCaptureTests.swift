import Testing

@testable import VoiceControlDaemon

@Test func audioTapAllowsCoreAudioSampleRateConversion() {
  #expect(
    AudioFormatReadiness.canInstallTap(
      hardwareSampleRate: 24_000,
      hardwareChannelCount: 1,
      clientSampleRate: 48_000,
      clientChannelCount: 1
    )
  )
  #expect(
    !AudioFormatReadiness.canInstallTap(
      hardwareSampleRate: 0,
      hardwareChannelCount: 1,
      clientSampleRate: 48_000,
      clientChannelCount: 1
    )
  )
}
