---
# voice-control-ua7f
title: Diagnose wake listener stopping after idle time
status: in-progress
type: bug
priority: normal
created_at: 2026-08-16T19:02:22Z
updated_at: 2026-08-20T15:26:51Z
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

## Current recurrence

- [x] Prevent microphone tap installation from racing a changing hardware format
- [x] Supervise the installed daemon so crashes restart automatically
- [x] Rebuild and verify the installed app through an audio-route change

The 2026-08-20 failure was an uncaught AVFAudio format-mismatch exception during route recovery, followed by a one-shot LaunchAgent that could not restart the crashed app.

## Recurrence fix

- AVFAudio tap-installation exceptions now become retryable Swift errors.
- The checked-in LaunchAgent supervises the bundle executable and restarts only unsuccessful exits.
- The installed build survived a default-input route change and resumed audio buffers.
- A forced process termination restarted under launchd with a new PID and resumed audio buffers.
