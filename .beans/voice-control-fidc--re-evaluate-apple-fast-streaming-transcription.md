---
# voice-control-fidc
title: Re-evaluate Apple fast streaming transcription
status: in-progress
type: task
priority: normal
created_at: 2026-08-15T17:27:49Z
updated_at: 2026-08-15T17:31:11Z
---

The prior SpeechTranscriber comparison enabled volatile results but omitted ReportingOption.fastResults or the progressiveTranscription preset. Apple documents fastResults as reducing latency with a smaller context window. Re-run the existing recorded corpus with the intended immediate live configuration, compare latency and semantic accuracy, then correct the engine decision.

- [x] Measure progressive Apple first-result latency on the saved corpus.
- [x] Compare progressive transcript quality with prior results.
- [ ] Correct the production engine decision.
- [ ] Delete the temporary re-evaluation code.

## Progressive live-preview result

The earlier probe used `.volatileResults` without `.fastResults`. Apple documents `fastResults` as using a smaller context window for lower latency, and `.progressiveTranscription` enables both options. Replaying the same five microphone recordings in real time with `.progressiveTranscription` produced first results at 2.098, 2.104, 2.085, 2.094, and 2.092 seconds, a 2.095-second mean. Parakeet previously averaged 2.946 seconds, so correctly configured Apple live preview is about 0.851 seconds faster.

Progressive final transcripts remained semantically equivalent on all five prompts. It also rendered `ChatGPT` correctly in the third prompt. The smaller fast-results context introduced no meaningful downstream quality loss in this corpus.
