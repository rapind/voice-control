import AVFoundation
import Testing

@testable import VoiceControlDaemon

@Test func audioCaptureUsesAirPodsHardwareFormatForTapAndRecording() throws {
  let hardwareFormat = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
  let staleClientFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!

  let plan = try #require(
    AudioCaptureFormatPlan.make(
      hardwareFormat: hardwareFormat,
      clientFormat: staleClientFormat
    )
  )

  #expect(plan.tapFormat.sampleRate == 24_000)
  #expect(plan.recordingFormat.sampleRate == 24_000)
  #expect(plan.tapFormat.channelCount == 1)
  #expect(plan.recordingFormat.channelCount == 1)
}
