---
# voice-control-fidc
title: Re-evaluate Apple fast streaming transcription
status: in-progress
type: task
created_at: 2026-08-15T17:27:49Z
updated_at: 2026-08-15T17:27:49Z
---

The prior SpeechTranscriber comparison enabled volatile results but omitted ReportingOption.fastResults or the progressiveTranscription preset. Apple documents fastResults as reducing latency with a smaller context window. Re-run the existing recorded corpus with the intended immediate live configuration, compare latency and semantic accuracy, then correct the engine decision.

- [ ] Measure progressive Apple first-result latency on the saved corpus.
- [ ] Compare progressive transcript quality with prior results.
- [ ] Correct the production engine decision.
- [ ] Delete the temporary re-evaluation code.
