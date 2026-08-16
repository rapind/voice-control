---
# voice-control-ua7f
title: Diagnose wake listener stopping after idle time
status: in-progress
type: bug
priority: normal
created_at: 2026-08-16T19:02:22Z
updated_at: 2026-08-16T19:14:48Z
---

- [x] Capture wake listener lifecycle evidence
- [x] Identify the listener failure mode: Core Audio stops the AVAudioEngine while the daemon remains alive
- [x] Add regression coverage and fix the failure
- [ ] Verify wake detection remains available

## Summary of Changes

- Core Audio can stop the microphone engine while the daemon remains alive.
- Added an idle health check that restarts audio capture and keyword recognition after that interruption.
- Added recovery policy coverage and rebuilt the running prototype.

## Notes

Manual verification after the usual idle window remains pending.
