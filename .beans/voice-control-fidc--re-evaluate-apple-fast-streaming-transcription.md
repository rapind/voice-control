---
# voice-control-fidc
title: Re-evaluate Apple fast streaming transcription
status: in-progress
type: task
priority: normal
created_at: 2026-08-15T17:27:49Z
updated_at: 2026-08-15T17:59:09Z
---

The prior SpeechTranscriber comparison enabled volatile results but omitted ReportingOption.fastResults or the progressiveTranscription preset. Apple documents fastResults as reducing latency with a smaller context window. Re-run the existing recorded corpus with the intended immediate live configuration, compare latency and semantic accuracy, then correct the engine decision.

- [x] Measure progressive Apple first-result latency on the saved corpus.
- [x] Compare progressive transcript quality with prior results.
- [ ] Correct the production engine decision.
- [ ] Delete the temporary re-evaluation code.

## Progressive live-preview result

The earlier probe used `.volatileResults` without `.fastResults`. Apple documents `fastResults` as using a smaller context window for lower latency, and `.progressiveTranscription` enables both options. Replaying the same five microphone recordings in real time with `.progressiveTranscription` produced first results at 2.098, 2.104, 2.085, 2.094, and 2.092 seconds, a 2.095-second mean. Parakeet previously averaged 2.946 seconds, so correctly configured Apple live preview is about 0.851 seconds faster.

Progressive final transcripts remained semantically equivalent on all five prompts. It also rendered `ChatGPT` correctly in the third prompt. The smaller fast-results context introduced no meaningful downstream quality loss in this corpus.

## End-to-end follow-up

- [x] Record a fresh AirPods corpus with short, medium, and long prompts.
- [x] Compare Apple progressive preview plus stream finalization against Parakeet rolling preview plus final file transcription.
- [x] Measure complete-workflow CPU, ANE, and energy use.
- [x] Commit the end-to-end comparison milestone before cleanup.

## Complete-workflow probe

Added a committed probe that records a fixed five-prompt corpus through the macOS default microphone, then replays each recording sequentially through Apple progressive preview plus stream finalization and Parakeet rolling preview plus final file transcription. Sequential replay avoids the CPU contention in the original simultaneous comparison. On the saved 11.9-second smoke prompt, Apple previewed at 2.088 seconds and finalized 0.045 seconds after audio ended; Parakeet previewed at 1.673 seconds and finalized after 0.183 seconds. This reverses the earlier preview comparison for that prompt and confirms that a fresh varied-length AirPods corpus is necessary.

## AirPods corpus results

Recorded five prompts through `Dave’s AirPods`, with audio durations of 2.1, 4.7, 8.0, 16.0, and 24.2 seconds. Sequential complete-workflow replay produced a 2.087-second mean Apple first preview and a 3.261-second mean Parakeet first preview. Apple finalized 0.090 seconds after audio ended on average; Parakeet finalized after 0.169 seconds. Both outputs were semantically suitable. The 4.908-second Parakeet preview on the short-command prompt is a likely contention outlier because unrelated app and Rust build work may run concurrently. Even excluding it, Parakeet averaged 2.849 seconds to first preview, 0.762 seconds slower than Apple. System-wide energy measurements must run without unrelated builds because `powermetrics` CPU and ANE totals would otherwise be invalid.

Added a privileged complete-workflow energy runner. It warms each engine after the release build, measures a 60-second idle baseline, then measures one identical full corpus through each production-shaped workflow. The runner refuses to start until the user confirms unrelated builds and sustained workloads are stopped.

## Complete-workflow energy result

The quiet run contained no `rustc` or `cargo` samples. Baseline combined CPU/GPU/ANE power averaged 67.8 mW. Apple progressive transcription averaged 112.8 mW over 59.29 seconds, about 2.67 J above baseline for the five-prompt corpus or 0.535 J per prompt. Parakeet rolling preview plus final transcription averaged 332.2 mW over 59.74 seconds, about 15.80 J above baseline or 3.159 J per prompt. Apple used approximately 83.1% less incremental energy for the complete production-shaped workflow.
