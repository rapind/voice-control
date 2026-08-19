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

@Test func audioCaptureNormalizesMultichannelVoiceProcessingOutputToMono() throws {
  let voiceProcessingFormat = AVAudioFormat(
    standardFormatWithSampleRate: 48_000,
    channels: 2
  )!
  let plan = try #require(
    AudioCaptureFormatPlan.make(
      hardwareFormat: voiceProcessingFormat,
      clientFormat: voiceProcessingFormat
    )
  )
  let source = try #require(
    AVAudioPCMBuffer(pcmFormat: voiceProcessingFormat, frameCapacity: 4)
  )
  source.frameLength = 4
  for frame in 0..<4 {
    source.floatChannelData![0][frame] = 0.25
    source.floatChannelData![1][frame] = 0.75
  }

  let normalized = try #require(
    AudioCaptureBufferNormalizer.normalize(
      source,
      outputFormat: plan.recordingFormat
    )
  )

  #expect(plan.tapFormat.channelCount == 2)
  #expect(plan.recordingFormat.channelCount == 1)
  #expect(normalized.format.channelCount == 1)
  #expect(normalized.frameLength == 4)
  #expect(
    Array(UnsafeBufferPointer(start: normalized.floatChannelData![0], count: 4)) == [
      0.25, 0.25, 0.25, 0.25,
    ])
}

@Test func ambientNoiseFloorRaisesSpeechThresholdAboveSteadyFanNoise() {
  var noiseFloor = AmbientNoiseFloor()

  for _ in 0..<100 {
    noiseFloor.observe(-42)
  }

  #expect(noiseFloor.speechThreshold(fallback: -45) == -34)
}

@Test func ambientNoiseFloorDoesNotTreatBriefSpeechAsRoomNoise() {
  var noiseFloor = AmbientNoiseFloor()

  for _ in 0..<100 {
    noiseFloor.observe(-55)
  }
  for _ in 0..<10 {
    noiseFloor.observe(-18)
  }

  #expect(noiseFloor.speechThreshold(fallback: -45) < -46)
}

@Test func ambientNoiseFloorMakesQuietRoomsMoreSensitive() {
  var noiseFloor = AmbientNoiseFloor()

  for _ in 0..<100 {
    noiseFloor.observe(-68)
  }

  #expect(noiseFloor.speechThreshold(fallback: -45) == -60)
}

@Test func ambientNoiseFloorUsesFallbackUntilCalibrated() {
  var noiseFloor = AmbientNoiseFloor()

  for _ in 0..<20 {
    noiseFloor.observe(-40)
  }

  #expect(noiseFloor.speechThreshold(fallback: -45) == -45)
}
