# ADR 0001: Persistent wake listening recovers after audio interruption

## Status

Accepted

## Decision

The daemon keeps microphone capture and keyword recognition active while it is waiting for a wake phrase. A wake phrase starts a prompt recording, while the capture stream remains the source for both keyword recognition and live transcription.

Audio capture uses the microphone's raw mono signal by default because Apple's call-oriented voice processing weakens far-field dictation. Voice processing remains available as an explicit configuration option, and its multichannel device output is normalized to mono before wake recognition, prompt transcription, recording, and level measurement. While waiting for a wake phrase, the daemon measures the ambient noise floor. After calibration, prompt speech is detected at 8 dB above that floor; the configured fixed threshold is used during startup.

Core Audio may stop `AVAudioEngine` and release the microphone assertion while the daemon process remains alive. While waiting for a wake phrase, the daemon checks whether audio capture is still running every five seconds. If capture has stopped, it restarts both audio capture and keyword recognition. It does not perform this recovery during an active prompt recording.

## Consequences

- Wake detection remains available after an idle Core Audio interruption without restarting the daemon.
- Silence detection adapts to the current input device and room without changing the signal sent to speech recognition.
- Recovery may take up to five seconds after the input engine stops.
- An active prompt keeps its captured audio and is never replaced by idle recovery.
- Wake listener recovery is an explicit runtime responsibility, not a side effect of process liveness.
