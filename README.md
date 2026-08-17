# Voice Control

Voice Control is a maintained private macOS tool for owning a complete voice transaction without wrapping OMP or interfering with the target application's rendering.

The daemon listens for a wake phrase, captures the frontmost window without changing focus, shows a live transcription while recording, finalizes that transcript, and presses Return. It uses Apple Speech progressive transcription on macOS 26 and FluidAudio Parakeet on macOS 14 and 15.

## Architecture decisions

The current design constraints are recorded in [Architecture Decision Records](docs/adr/README.md).

## Before running

1. On macOS 14 or 15, load Parakeet once in TypeWhisper. The tool reuses the model files already stored in FluidAudio's shared cache. TypeWhisper does not need to remain open. On macOS 26, the app installs and uses Apple's on-device `en-US` speech asset.
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
vocabulary = ["bean"]

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
share_session = ["share session"]
stop_sharing = ["stop sharing"]
focus_1 = ["focus one"]
focus_2 = ["focus two"]
focus_3 = ["focus three"]
focus_4 = ["focus four"]
focus_5 = ["focus five"]
focus_6 = ["focus six"]
focus_7 = ["focus seven"]
focus_8 = ["focus eight"]
focus_9 = ["focus nine"]

[applications.chatgpt.commands]
focus = ["focus chat"]
new_chat = ["new chat"]
focus_1 = ["focus one"]
focus_2 = ["focus two"]
focus_3 = ["focus three"]
focus_4 = ["focus four"]
focus_5 = ["focus five"]
focus_6 = ["focus six"]
focus_7 = ["focus seven"]
focus_8 = ["focus eight"]
focus_9 = ["focus nine"]

[applications.chrome.commands]
focus = ["focus chrome"]
focus_1 = ["focus one"]
focus_2 = ["focus two"]
focus_3 = ["focus three"]
focus_4 = ["focus four"]
focus_5 = ["focus five"]
focus_6 = ["focus six"]
focus_7 = ["focus seven"]
focus_8 = ["focus eight"]
focus_9 = ["focus nine"]
```

Save the file and the app applies valid changes within about one second. You do not need to rebuild or restart it. Invalid TOML leaves the last working configuration active and shows a config error in the menu. Older `target` settings are accepted but no longer control routing.

`vocabulary` lists words and short phrases to bias Apple Speech toward during dictation. It is a recognition hint, not a replacement rule, so adding `bean` does not turn legitimate uses of `being` into `bean`.

The wake phrase starts recording without changing focus. Dictation is bound to whichever window was frontmost when recording started. Application-focus phrases, `focus ghost tee`, `focus chat`, and `focus chrome`, execute after a wake phrase.

Focus one through eight and the scroll commands execute directly from idle. In Ghostty, focus commands send Control+Option+1 through Control+Option+8, and in ChatGPT or Chrome they send Command+1 through Command+8. `scroll up` and `scroll down` send mouse wheel events to the frontmost window. If another application was frontmost, the phrase is consumed without sending a keyboard shortcut.

Use another configuration file when launching if needed:

```bash
./run-prototype.sh --config "$HOME/path/to/config.toml"
```

On first launch, macOS asks for Microphone, Speech Recognition, and Accessibility permission. Accessibility is required for typing dictation, focusing applications, and sending keyboard shortcuts.

The menu-bar item shows the current state and active control phrases. Use **Open Configuration** there to edit the TOML file. Quit it from that menu or press Control-C in the launching terminal.

## Application commands

The wake phrase starts recording. Once recording, command aliases execute immediately from Apple Speech partials and do not require a submit phrase. `focus one` through `focus eight`, `scroll up`, and `scroll down` are the exception: they execute directly from idle without the wake phrase.

Ghostty, ChatGPT, and Chrome support:

- `focus one` through `focus nine` after a wake phrase
- `scroll up` and `scroll down` after a wake phrase
- Their global application focus phrase

For Ghostty, `new chat` opens a new tab, types `codex`, and presses Return. `clear context` sends `/clear`, and `compact context` sends `/compact`; both press Return. `quit session` sends Control-D to the foreground terminal process. `start session` types `omp` and presses Return. `share session` sends `/collab` and `stop sharing` sends `/collab stop`, each followed by Return. Numbered focus commands send Control+Option+1 through Control+Option+9, matching the recommended Herdr workspace bindings. For ChatGPT, `new chat` sends Command-N. Chrome does not define a `new chat` command. Numbered focus commands in ChatGPT and Chrome send Command-1 through Command-9.

`scroll up` and `scroll down` send mouse scroll wheel events to the center of the frontmost window, so they scroll whatever is on screen without moving the cursor or changing focus.

All other speech remains a normal prompt. On macOS 26, Apple progressive results revise the visible text while recording and finalize through the end of the same audio stream. On macOS 14 and 15, rolling full-context Parakeet passes provide the preview and a final file pass remains authoritative.

The configured submit phrase creates an audio cutoff. The phrase itself and anything spoken after it are excluded from final transcription. Say a configured cancel phrase to clear the live preview, discard the recording, and return to wake listening without submitting.

## Operational limits

- Dictation stays bound to the window captured at wake time. Changing windows during recording stops live typing rather than redirecting text.
- Apple Speech preview results may revise earlier words until stream finalization. The Parakeet fallback updates about every 1.5 seconds and replaces its preview with the final full-context pass.
- Live preview typing stops rather than sending text to an application that is no longer frontmost.
- Model downloading and Hugging Face authentication are deliberately out of scope for the Parakeet fallback. It fails clearly when the shared cached model is missing. Apple Speech assets are installed through `AssetInventory`.
- Silence detection uses a configurable RMS threshold, not a neural VAD.
- The app is ad-hoc signed with a stable identifier-only designated requirement. This avoids a paid Apple developer account and should preserve Accessibility approval across local rebuilds. It is appropriate for this private local tool, but weaker than certificate-backed signing because another local app using the same bundle identifier could satisfy the requirement.

