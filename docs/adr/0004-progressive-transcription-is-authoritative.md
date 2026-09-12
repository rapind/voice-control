# ADR 0004: Progressive transcription is authoritative

## Status

Accepted

## Decision

Apple progressive transcription is the authoritative prompt text. Apple finalization and file retranscription are never used for prompt submission. If live recognition produces no usable text, submission fails instead of asking Apple to reinterpret the complete recording.

Each visible progressive preview records the latest prompt audio position it covers. Submission closes the live audio input and waits up to one second for a progressive callback that covers the latest detected speech. If Apple still reports incomplete timestamp coverage, Voice Control submits the newest usable progressive text. If draining produces no text, it keeps the visible preview.

The configured submit phrase triggers submission but remains in the transcript. The wake and submit phrases may be the same because their meaning depends on whether Voice Control is idle or recording. Prompt capture starts a fresh keyword-recognition request so the opening phrase cannot carry into the recording state and trigger submission. Voice Control does not trim recorded audio, remove the submit phrase, or remove partial words that resemble the submit phrase. The receiving agent treats a trailing submit phrase as control residue. This avoids deleting real dictated content when Apple revises text or reports unstable timestamps near the end of a recording.

Silence never submits a prompt. The configured submit phrase sends immediately, and a six-minute maximum duration prevents an abandoned recording from running forever.

The Parakeet fallback continues to transcribe the finished file because its rolling live preview is intended as feedback rather than its authoritative full-context result.

## Consequences

- Apple’s final pass cannot replace a useful live preview with a contextually worse guess.
- Submission no longer depends on aligning Apple timestamps with the audio capture timeline.
- A trailing submit phrase is visible to clients that do not know the voice-control convention.
- Agents configured for voice-control input must ignore the trailing submit phrase rather than act on it.
- The target LLM receives all recognized prompt content and can interpret it using conversation context.

## References

- [Apple: `SFTranscriptionSegment.timestamp`](https://developer.apple.com/documentation/speech/sftranscriptionsegment/timestamp)
- [Apple: `SFSpeechAudioBufferRecognitionRequest`](https://developer.apple.com/documentation/speech/sfspeechaudiobufferrecognitionrequest)
