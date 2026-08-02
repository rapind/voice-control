# Prototype Notes

## Question

Can one small macOS process own a hands-free Codex prompt transaction without wrapping Codex or changing how Ghostty renders it?

## What was built

- Apple Speech listens continuously for configurable wake and submit phrases.
- AVAudioEngine records the prompt and supplies a silence fallback.
- FluidAudio loads Parakeet v3 directly from TypeWhisper's existing shared model cache.
- The final transcript is pasted into the active Ghostty process, then Return is sent after the paste completes.
- A menu-bar item exposes the current state.

## What the prototype has established

- TypeWhisper does not need to run and its HTTP API is not part of the design.
- The existing 469 MB model can be reused in place, with no second download or Hugging Face token.
- The daemon builds and loads as a locally signed macOS app without a paid Apple developer account.
- macOS privacy permissions work only when the assembled app is launched through Launch Services. Executing the binary inside the bundle directly makes TCC ignore the bundle usage descriptions and abort the process.
- A complete live transaction succeeded: `Ghostee` entered recording, the submit phrase ended recording, Parakeet transcribed `Test`, Ghostty became frontmost, the prompt was pasted, Return was sent, and Codex replied `Received`.
- Immediate focus and direct commands are verified: `Ghostee` focused Ghostty immediately, then `new tab` created a tab without requiring the submit phrase.
- Live verification succeeded: `ghost cancel` discarded an in-progress prompt and returned directly to wake listening without inserting or submitting text.
- Apple Speech may spell product names phonetically. Vocabulary hints and aliases are required for a dependable custom wake phrase.
- `NSRunningApplication.activate()` and Launch Services both reported success without making an already-running Ghostty frontmost. An explicit Apple event successfully activates it, and the daemon verifies the actual frontmost PID before sending keystrokes.
- Accessibility permission did not stick because the default ad-hoc designated requirement was the changing binary hash. Builds now use the stable requirement `identifier "com.daverapin.voice-control-prototype"`, allowing local rebuilds to retain one Accessibility grant without an Apple developer certificate.
- The old hash-based Accessibility record had to be reset once with `tccutil reset Accessibility com.daverapin.voice-control-prototype`, then the stable-signed installed app was granted and reopened.
- Voice phrases and fixed Ghostty command aliases now load from `~/.config/voice-control/config.toml`. Valid saves reload automatically; invalid saves leave the last good configuration running.
- Live reload was verified without restarting the app: adding `computer` to `wake` activated recording and `ghost cancel` discarded it. The temporary alias was then removed.

## Still to establish with extended use

- Whether the simple RMS silence threshold behaves well with AirPods, room noise, and walking around.
- Whether the `Ghostee` aliases remain reliable across the room and over many recognition-task recycling cycles.
- Whether focusing Ghostty, pasting, and pressing Return remains reliable across repeated prompts, tab changes, and macOS Spaces.

## Recommendation

Keep this code only if the live voice loop feels dependable. If it does, harden this prototype into a launch agent and add model download recovery, stable signing, configuration storage, and better voice activity detection. If it does not, delete it and keep TypeWhisper as manual dictation rather than deepening the wrong interaction model.
