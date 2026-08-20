# ADR 0004: Recording edits use the capture timeline

## Status

Accepted

## Decision

Any operation that cuts or aligns recorded audio uses timestamps produced by `AudioCapture`. The capture timeline advances by the duration of each delivered audio buffer and supplies both the recording start time and audio-level sample times.

The submit phrase is detected from Apple Speech text, but its recording cutoff does not use `SFTranscriptionSegment.timestamp`. Live partial results may expose a newly recognized segment with a timestamp and duration of zero, then replace those placeholders with its actual request-relative timing after the segment stabilizes. Submission must remain responsive, and submit detection stops keyword recognition immediately, so stable segment timing may never arrive.

Instead, audio-level samples identify speech bursts on the capture timeline. When Apple Speech recognizes a submit phrase, the recording is cut just before the latest speech burst that follows a distinct period of silence. If there is no distinct later burst, the daemon keeps the full recording and removes the trailing submit phrase from the final text rather than risking deletion of the prompt.

When a recording is cut, final transcription reads the cut file instead of returning the already-produced live transcript. An empty cut is rejected before file transcription.

## Consequences

- Recognition-request timestamps may be used to describe stabilized recognition results, but never to edit captured audio.
- Recognition task recycling and input-device changes cannot put a recording cutoff on a different clock from the recording itself.
- A brief pause before the submit phrase gives the cleanest audio cut.
- Continuous speech ending in a submit phrase may leave that phrase in the audio sent to transcription, but final text cleanup still removes it.
- A bad cutoff fails explicitly instead of sending an empty audio file to a transcriber that may wait indefinitely.

## References

- [Apple: `SFTranscriptionSegment.timestamp`](https://developer.apple.com/documentation/speech/sftranscriptionsegment/timestamp)
- [Apple: `SFSpeechAudioBufferRecognitionRequest`](https://developer.apple.com/documentation/speech/sfspeechaudiobufferrecognitionrequest)
