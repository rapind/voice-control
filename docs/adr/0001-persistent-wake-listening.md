# ADR 0001: Persistent wake listening recovers after audio interruption

## Status

Accepted

## Decision

The daemon keeps microphone capture and keyword recognition active while it is waiting for a wake phrase. A wake phrase starts a prompt recording, while the capture stream remains the source for both keyword recognition and live transcription.

Audio capture uses the microphone's raw mono signal by default because Apple's call-oriented voice processing weakens far-field dictation. Voice processing remains available as an explicit configuration option, and its multichannel device output is normalized to mono before wake recognition, prompt transcription, recording, and level measurement. While waiting for a wake phrase, the daemon measures the ambient noise floor. After calibration, prompt speech is detected at 8 dB above that floor; the configured fixed threshold is used during startup.

Audio capture follows the macOS default input device. Connecting AirPods may change both the default input and output, even when a USB microphone was previously selected. An `AVAudioEngine` configuration change while waiting for a wake phrase stops capture immediately, waits for the new route to settle, and restarts capture and keyword recognition using the new input's current hardware format. The ambient noise floor is recalibrated for that input. Disconnecting the device follows the same path back to the next system default.

Core Audio may also stop `AVAudioEngine` and release the microphone assertion while the daemon process remains alive. While waiting for a wake phrase, the daemon checks every five seconds that the engine is running and still delivering audio buffers. If either check fails, it restarts both audio capture and keyword recognition. It does not perform route recovery during an active prompt recording.

## Consequences

- Wake detection remains available after an idle Core Audio interruption without restarting the daemon.
- Silence detection adapts to the current input device and room without changing the signal sent to speech recognition.
- AirPods can become both input and output automatically, while a manually selected USB input remains in use only until macOS changes the system default.
- Route recovery uses the new device's current hardware sample rate. The same AirPods may negotiate either 24 kHz or 48 kHz mono across different connections, so capture must not assume a fixed Bluetooth input format.
- Recovery may take up to five seconds after the input engine stops.
- An active prompt keeps its captured audio and is never replaced by idle recovery.
- Wake listener recovery is an explicit runtime responsibility, not a side effect of process liveness.

## References

- [Apple: Responding to audio route changes](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes)
- [Apple: `AVAudioEngineConfigurationChangeNotification`](https://developer.apple.com/documentation/avfaudio/avaudioengineconfigurationchangenotification)
- [Apple: High-quality Bluetooth recording](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/bluetoothhighqualityrecording)
