# ADR 0004: Dictation uses local Parakeet

## Status

Accepted

## Decision

Dictation uses the cached Parakeet v3 model through the pinned FluidAudio dependency on every supported macOS version. The operating system version does not select the dictation engine. Recognition changes require a deliberate application or model update.

Rolling full-context recognition updates the live preview while recording. Parakeet may revise visible text, including earlier words. Submission uses a final Parakeet pass over the complete recording. Both live and final results may correct words and punctuation, but a shorter result whose words only repeat a prefix of the accepted transcript cannot retract its remaining text. Prefix comparison ignores capitalization and punctuation. A new recording and explicit cancellation reset this checkpoint. The receiving LLM interprets recognition mistakes that remain in the submitted text.

Apple Speech recognizes wake phrases and commands, including the configured submit phrase. The wake and submit phrases may be the same because their meaning depends on whether Voice Control is idle or recording. Prompt capture starts a fresh keyword-recognition request so the opening phrase cannot carry into the recording state and trigger submission.

The configured submit phrase triggers submission but remains in the transcript. Voice Control does not trim recorded audio, remove the submit phrase, or remove partial words that resemble it. The receiving agent treats a trailing submit phrase as control residue.

Silence never submits a prompt. The configured submit phrase sends immediately, and a six-minute maximum duration prevents an abandoned recording from running forever.

## Consequences

- Dictation reuses local model files without downloading updates. The shared cache must contain Parakeet v3 before startup.
- Model files in the shared cache are not checksum-pinned by this application. Replacing those files can change recognition behavior.
- Earlier preview text can change during recording and at submission. Prefix-only retractions retain the accepted tail, which can also retain recognition mistakes until a later correction changes the words.
- Live preview types recognition updates without focus or field-readiness checks. The user controls input focus throughout dictation. There is no capability-based buffering until submission.
- Corrections read the captured application's current field text and selection, confirm the replacement range, then replace it in one operation. There is no separate deletion phase before replacement text is sent. Native access to the text and selection is required for corrections; insertions do not query the field.
- A missing focused field during a correction triggers best-effort native Accessibility activation when the client exposes that setting. Live edits do not require exact field-value acknowledgement because clients can expose placeholder text that disappears on insertion.
- Wake and command recognition still depend on Apple's speech engine.
- A trailing submit phrase is visible to clients that do not know the voice-control convention.
- Agents configured for voice-control input must ignore the trailing submit phrase rather than act on it.
