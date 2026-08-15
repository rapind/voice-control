---
# voice-control-f1ml
title: Evaluate Apple SpeechTranscriber on macOS 26
status: todo
type: feature
priority: normal
tags:
    - enhancement
    - apple-speech
    - needs-info
created_at: 2026-08-15T06:28:20Z
updated_at: 2026-08-15T07:42:17Z
---

## Goal

Compare Apple `SpeechAnalyzer` and `SpeechTranscriber` with the current FluidAudio Parakeet implementation on an M4 MacBook Air after the machine is upgraded to macOS 26.

## Current blocker

The development machine is running macOS 15.7.8 (Darwin 24.6). `SpeechAnalyzer` and `SpeechTranscriber` require macOS 26, so testing now would only evaluate the legacy `SFSpeechRecognizer` already used for wake and control commands.

## Resume after upgrading

When a new session starts on macOS 26:

- Confirm `sw_vers` reports macOS 26.
- Start this bean before changing transcription code.
- Build an availability-gated, temporary comparison path using `SpeechAnalyzer` and `SpeechTranscriber`, not legacy `SFSpeechRecognizer`.
- Keep the current FluidAudio Parakeet path intact until the comparison is measured.
- Run both engines against the same real dictated prompts.

## Prototype scope

- Add an availability-gated, temporary Apple transcription mode.
- Use volatile results for live preview and finalized results for submission.
- Keep Parakeet as the fallback for macOS 14 and 15.
- Confirm Apple model assets remain on-device.
- Compare first-preview latency, finalization latency, transcription accuracy, peak memory, CPU/Neural Engine use, and battery impact against Parakeet on the M4 Air.

## Acceptance criteria

- Run both engines on the same real dictated prompts.
- Record measured latency and resource results, not impressions alone.
- Decide whether Apple Speech replaces Parakeet, remains optional, or is rejected.
- Delete the temporary prototype path after the decision or absorb the selected implementation cleanly.
