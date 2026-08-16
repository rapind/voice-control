# Voice Control Prototype

This is throwaway code answering one question: can one small macOS process reliably own the complete voice transaction without wrapping Codex or interfering with the target application's rendering?

The daemon listens for a wake phrase, captures the frontmost window without changing focus, shows a live transcription while recording, finalizes that transcript, and presses Return. It uses Apple Speech progressive transcription on macOS 26 and FluidAudio Parakeet on macOS 14 and 15.

## Before running

1. On macOS 14 or 15, load Parakeet once in TypeWhisper. The prototype reuses the model files already stored in FluidAudio's shared cache. TypeWhisper does not need to remain open. On macOS 26, the app installs and uses Apple's on-device `en-US` speech asset.
2. Run Ghostty, ChatGPT, or Google Chrome when you want to use their application shortcuts.

## Run the installed app

The working bundle is installed at:

```text
~/Applications/Voice Control Prototype.app
```

Launch it with Spotlight or:

```bash
open "$HOME/Applications/Voice Control Prototype.app"
```

The local build uses a stable identifier-based designated requirement so macOS can preserve Accessibility permission across ad-hoc rebuilds. Install it at a stable path before granting permission.

## Build during development

```bash
./run-prototype.sh
```

The editable configuration lives at:

```text
~/.config/voice-control/config.toml
```

The current setup is:

```toml
# Voice Control reloads this file automatically after you save it.
wake = ["pewter", "pooter", "pyewter", "computer"]
submit = ["send it", "sent it"]
cancel = ["cancel it"]

silence_seconds = 4
silence_threshold_db = -45
maximum_recording_seconds = 90

[applications.ghostty.commands]
focus = ["focus ghost tee"]
new_chat = ["new chat"]
clear_context = ["clear context"]
compact_context = ["compact context"]
interrupt_session = ["quit session"]
start_session = ["start session"]
next = ["focus next"]
previous = ["focus previous", "focus prev"]
focus_1 = ["focus 1"]
focus_2 = ["focus 2"]
focus_3 = ["focus 3"]
focus_4 = ["focus 4"]
focus_5 = ["focus 5"]
focus_6 = ["focus 6"]
focus_7 = ["focus 7"]
focus_8 = ["focus 8"]
focus_9 = ["focus 9"]

[applications.chatgpt.commands]
focus = ["focus chat"]
new_chat = ["new chat"]
focus_1 = ["focus 1"]
focus_2 = ["focus 2"]
focus_3 = ["focus 3"]
focus_4 = ["focus 4"]
focus_5 = ["focus 5"]
focus_6 = ["focus 6"]
focus_7 = ["focus 7"]
focus_8 = ["focus 8"]
focus_9 = ["focus 9"]

[applications.chrome.commands]
focus = ["focus chrome"]
focus_1 = ["focus 1"]
focus_2 = ["focus 2"]
focus_3 = ["focus 3"]
focus_4 = ["focus 4"]
focus_5 = ["focus 5"]
focus_6 = ["focus 6"]
focus_7 = ["focus 7"]
focus_8 = ["focus 8"]
focus_9 = ["focus 9"]
```

Save the file and the app applies valid changes within about one second. You do not need to rebuild or restart it. Invalid TOML leaves the last working configuration active and shows a config error in the menu. Older `target` settings are accepted but no longer control routing.

The wake phrase starts recording without changing focus. Dictation is bound to whichever window was frontmost when recording started. Direct focus phrases are global: `focus ghost tee`, `focus chat`, and `focus chrome`.

Other commands use the supported application that was frontmost at wake time. In Ghostty, `focus 1` sends Control+Option+1 for direct Herdr workspace switching. In ChatGPT and Chrome, it sends Command+1. If another application was frontmost, the phrase is consumed without sending a keyboard shortcut.

Use another configuration file when launching if needed:

```bash
./run-prototype.sh --config "$HOME/path/to/config.toml"
```

On first launch, macOS asks for Microphone, Speech Recognition, and Accessibility permission. Accessibility is required for typing dictation, focusing applications, and sending keyboard shortcuts.

The menu-bar item shows the current state and active control phrases. Use **Open Configuration** there to edit the TOML file. Quit it from that menu or press Control-C in the launching terminal.

## Application commands

The wake phrase only starts recording. It does not focus an application. Command aliases execute immediately from Apple Speech partials and do not require a submit phrase.

Ghostty, ChatGPT, and Chrome support:

- `focus 1` through `focus 9`
- Their global application focus phrase

For Ghostty, `new chat` opens a new tab, types `codex`, and presses Return. `clear context` sends `/clear`, and `compact context` sends `/compact`; both press Return. `quit session` sends Control-C to the foreground terminal process. `start session` types `omp` and presses Return. Ghostty also supports `focus next` and `focus previous`. Numbered focus commands send Control+Option+1 through Control+Option+9, matching the recommended Herdr workspace bindings. For ChatGPT, `new chat` sends Command-N. Chrome does not define a `new chat` command. Numbered focus commands in ChatGPT and Chrome send Command-1 through Command-9.

All other speech remains a normal prompt. On macOS 26, Apple progressive results revise the visible text while recording and finalize through the end of the same audio stream. On macOS 14 and 15, rolling full-context Parakeet passes provide the preview and a final file pass remains authoritative.

The configured submit phrase creates an audio cutoff. The phrase itself and anything spoken after it are excluded from final transcription. Say a configured cancel phrase to clear the live preview, discard the recording, and return to wake listening without submitting.

## Prototype limits

- Dictation stays bound to the window captured at wake time. Changing windows during recording stops live typing rather than redirecting text.
- Apple Speech preview results may revise earlier words until stream finalization. The Parakeet fallback updates about every 1.5 seconds and replaces its preview with the final full-context pass.
- Live preview typing stops rather than sending text to an application that is no longer frontmost.
- Model downloading and Hugging Face authentication are deliberately out of scope for the Parakeet fallback. It fails clearly when the shared cached model is missing. Apple Speech assets are installed through `AssetInventory`.
- Silence detection uses a configurable RMS threshold, not a neural VAD.
- The app is ad-hoc signed with a stable identifier-only designated requirement. This avoids a paid Apple developer account and should preserve Accessibility approval across local rebuilds. It is appropriate for this private local tool, but weaker than certificate-backed signing because another local app using the same bundle identifier could satisfy the requirement.

Delete or replace this prototype after the interaction model has been tested.
