# Voice Control Prototype

This is throwaway code answering one question: can one small macOS process reliably own the complete voice transaction without wrapping Codex or interfering with the target application's rendering?

The daemon listens for a wake phrase, focuses the configured application, shows a live transcription while recording, finalizes that transcript, and presses Return. It uses Apple Speech progressive transcription on macOS 26 and FluidAudio Parakeet on macOS 14 and 15.

## Before running

1. On macOS 14 or 15, load Parakeet once in TypeWhisper. The prototype reuses the model files already stored in FluidAudio's shared cache. TypeWhisper does not need to remain open. On macOS 26, the app installs and uses Apple's on-device `en-US` speech asset.
2. Run Ghostty or ChatGPT, whichever is selected by `target` in the configuration.

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

The current Ghostty setup is:

```toml
# Voice Control reloads this file automatically after you save it.
target = "ghostty"
wake = ["pewter", "pooter", "pyewter", "computer"]
submit = ["send it", "sent it"]
cancel = ["cancel it"]

silence_seconds = 4
silence_threshold_db = -45
maximum_recording_seconds = 90

[applications.ghostty.commands]
focus = ["focus term"]
new_chat = ["new chat"]
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
focus = ["focus chatgpt"]
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
```

Set `target` to either `ghostty` or `chatgpt`. Save the file and the app applies valid changes within about one second. You do not need to rebuild or restart it. Invalid TOML leaves the last working configuration active and shows a config error in the menu.

Command phrases are scoped to their application. Only the active target's command table is sent to speech recognition or evaluated at runtime. The same phrase, such as `focus 1`, can safely mean tab 1 in Ghostty and chat 1 in ChatGPT.

Use another configuration file when launching if needed:

```bash
./run-prototype.sh --config "$HOME/path/to/config.toml"
```

On first launch, macOS asks for Microphone, Speech Recognition, and Accessibility permission. Accessibility is required for focusing the target application and sending keyboard input.

The menu-bar item shows the current state and active control phrases. Use **Open Configuration** there to edit the TOML file. Quit it from that menu or press Control-C in the launching terminal.

## Application commands

The configured target is focused as soon as any wake phrase is recognized. Its command aliases execute immediately from Apple Speech partials and do not require a submit phrase.

Both targets support:

- `new chat`
- `focus 1` through `focus 9`
- An application-specific focus phrase

For Ghostty, `new chat` opens a new tab, types `codex`, and presses Return. Ghostty also supports `focus next` and `focus previous`. For ChatGPT, `new chat` sends Command-N. Numbered focus commands send Command-1 through Command-9 to the selected application.

All other speech remains a normal prompt. On macOS 26, Apple progressive results revise the visible text while recording and finalize through the end of the same audio stream. On macOS 14 and 15, rolling full-context Parakeet passes provide the preview and a final file pass remains authoritative.

The configured submit phrase creates an audio cutoff. The phrase itself and anything spoken after it are excluded from final transcription. Say a configured cancel phrase to clear the live preview, discard the recording, and return to wake listening without submitting.

## Prototype limits

- It targets the selected application's frontmost process when the wake phrase is detected. If another app is frontmost, it falls back to the selected running application.
- Apple Speech preview results may revise earlier words until stream finalization. The Parakeet fallback updates about every 1.5 seconds and replaces its preview with the final full-context pass.
- Live preview typing stops rather than sending text to an application that is no longer frontmost.
- Model downloading and Hugging Face authentication are deliberately out of scope for the Parakeet fallback. It fails clearly when the shared cached model is missing. Apple Speech assets are installed through `AssetInventory`.
- Silence detection uses a configurable RMS threshold, not a neural VAD.
- The app is ad-hoc signed with a stable identifier-only designated requirement. This avoids a paid Apple developer account and should preserve Accessibility approval across local rebuilds. It is appropriate for this private local tool, but weaker than certificate-backed signing because another local app using the same bundle identifier could satisfy the requirement.

Delete or replace this prototype after the interaction model has been tested.
