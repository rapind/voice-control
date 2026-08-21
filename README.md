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

Start the installed launch service with:

```bash
launchctl kickstart -k "gui/$(id -u)/com.daverapin.voice-control-prototype"
```

The launch service runs the executable inside this bundle directly. It restarts the app after a crash, but a successful exit from **Quit Voice Control** remains stopped until you start it again or rebuild it. The local build uses a stable identifier-based designated requirement so macOS can preserve Accessibility permission across ad-hoc rebuilds. Install it at a stable path before granting permission.

## Build during development

```bash
./run-prototype.sh
```

The script rebuilds and replaces the same app bundle under `~/Applications`, installs its launch service, and leaves it running. It does not leave a second development app registered with macOS.

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

silence_seconds = 5
silence_threshold_db = -45
maximum_recording_seconds = 90
voice_processing = false

[applications.ghostty.commands]
focus = ["focus ghost tee"]
new_chat = ["new tab"]
close_tab = ["close tab"]
clear_context = ["clear context"]
compact_context = ["compact context"]
interrupt_session = ["quit session"]
start_session = ["start session"]
share_session = ["share session"]
stop_sharing = ["stop sharing"]
focus_1 = ["focus one", "folk one"]
focus_2 = ["focus two", "folk two"]
focus_3 = ["focus three", "folk three"]
focus_4 = ["focus four", "folk four"]
focus_5 = ["focus five", "folk five"]
focus_6 = ["focus six", "folk six"]
focus_7 = ["focus seven", "folk seven"]
focus_8 = ["focus eight", "folk eight"]
focus_9 = ["focus nine", "folk nine"]

[applications.chatgpt.commands]
focus = ["focus chat"]
new_chat = ["new tab"]
close_tab = ["close tab"]
clear_context = ["clear context"]
scroll_end = ["scroll end"]
focus_1 = ["focus one", "folk one"]
focus_2 = ["focus two", "folk two"]
focus_3 = ["focus three", "folk three"]
focus_4 = ["focus four", "folk four"]
focus_5 = ["focus five", "folk five"]
focus_6 = ["focus six", "folk six"]
focus_7 = ["focus seven", "folk seven"]
focus_8 = ["focus eight", "folk eight"]
focus_9 = ["focus nine", "folk nine"]

[applications.chrome.commands]
focus = ["focus chrome"]
focus_1 = ["focus one", "folk one"]
focus_2 = ["focus two", "folk two"]
focus_3 = ["focus three", "folk three"]
focus_4 = ["focus four", "folk four"]
focus_5 = ["focus five", "folk five"]
focus_6 = ["focus six", "folk six"]
focus_7 = ["focus seven", "folk seven"]
focus_8 = ["focus eight", "folk eight"]
focus_9 = ["focus nine", "folk nine"]
```

Save the file and the app applies valid changes within about one second. You do not need to rebuild or restart it. Invalid TOML leaves the last working configuration active and shows a config error in the menu. Older `target` settings are accepted but no longer control routing.

`vocabulary` lists words and short phrases to bias Apple Speech toward during dictation. It is a recognition hint, not a replacement rule, so adding `bean` does not turn legitimate uses of `being` into `bean`.

The wake phrase starts recording without changing focus. Dictation is bound to whichever window was frontmost when recording started. Application-focus phrases, `focus ghost tee`, `focus chat`, and `focus chrome`, execute after a wake phrase.

`focus one` or `folk one` through eight, the scroll commands, and the media commands execute directly from idle. In Ghostty, numbered focus commands send Control+Option+1 through Control+Option+8, and in ChatGPT or Chrome they send Command+1 through Command+8. `scroll up` and `scroll down` send mouse wheel events to the frontmost window. If another application was frontmost, the phrase is consumed without sending a keyboard shortcut.

Use another configuration file when launching if needed:

```bash
./run-prototype.sh --config "$HOME/path/to/config.toml"
```

On first launch, macOS asks for Microphone, Speech Recognition, and Accessibility permission. Accessibility is required for typing dictation, focusing applications, and sending keyboard shortcuts.

The menu-bar item shows the current state and active control phrases. Use **Open Configuration** there to edit the TOML file. Quit it from that menu. Because the launch service treats a successful exit as intentional, it will not immediately reopen the app.

## Application commands

The wake phrase starts recording. Once recording, command aliases execute immediately from Apple Speech partials and do not require a submit phrase. `focus one` or `folk one` through eight, the scroll commands, the context commands, and the media commands are the exception: they execute directly from idle without the wake phrase.

`sleep MacBook` also executes directly from idle and immediately asks macOS to sleep. It does not require the wake phrase.

Ghostty, ChatGPT, and Chrome support:

- `focus one` or `folk one` through nine after a wake phrase
- `scroll up` and `scroll down` after a wake phrase
- Their global application focus phrase

ChatGPT also supports `scroll end`, which jumps toward the latest generated output.

`media launch` opens the installed YouTube Music web app, then restores focus to the application you were using. `media play`, `media pause`, `media next`, and `media previous` send macOS system media events without changing application focus. They control the current macOS media session, which works with YouTube Music once it owns that session. `media play` and `media pause` both send the system play/pause toggle because macOS does not expose separate play and pause media keys.

For Ghostty, `new tab` creates and focuses a Herdr workspace through Herdr's API, while `close tab` closes the focused Herdr workspace. `clear context` sends `/clear`, and `compact context` sends `/compact`. Slash commands wait for the client to process the paste, then send Return twice so command completion cannot consume the only Return. `quit session` sends Control-D to the foreground terminal process. `start session` types `omp` and presses Return. `share session` sends `/collab` and `stop sharing` sends `/collab stop`. Numbered focus commands send Control+Option+1 through Control+Option+9, matching the configured Herdr workspace bindings. In ChatGPT, `new tab` and `clear context` send Command-N to open a fresh chat, while `close tab` sends Command-W. The ChatGPT client does not implement the Codex CLI `/clear` command. Chrome does not define new or close tab commands. Numbered focus commands in ChatGPT and Chrome send Command-1 through Command-9.

`scroll up` and `scroll down` send mouse scroll wheel events to the center of the frontmost window, so they scroll whatever is on screen without moving the cursor or changing focus.

All other speech remains a normal prompt. On macOS 26, Apple progressive results revise the visible text while recording, and the last useful live revision is authoritative. Voice Control does not ask Apple to rewrite it during a final pass. On macOS 14 and 15, rolling full-context Parakeet passes provide the preview and a final file pass remains authoritative.

The configured submit phrase creates an audio cutoff. After a brief pause, Voice Control also checkpoints the live preview before the submit phrase begins, so the phrase and anything spoken after it are excluded even when Apple spells the phrase incorrectly. Say a configured cancel phrase to clear the live preview, discard the recording, and return to wake listening without submitting.

## Operational limits

- Dictation stays bound to the window captured at wake time. Changing windows during recording stops live typing rather than redirecting text.
- Apple Speech preview results may revise earlier words while recording, but Voice Control submits the last useful live revision without Apple’s final rewrite. The Parakeet fallback updates about every 1.5 seconds and replaces its preview with the final full-context pass.
- Live preview typing stops rather than sending text to an application that is no longer frontmost.
- Model downloading and Hugging Face authentication are deliberately out of scope for the Parakeet fallback. It fails clearly when the shared cached model is missing. Apple Speech assets are installed through `AssetInventory`.
- Apple voice processing can be enabled with `voice_processing = true`, but it is disabled by default because its call-oriented filtering weakens far-field dictation. When enabled, its multichannel device output is normalized to mono before recognition and recording.
- Silence detection measures the processed room noise while waiting for the wake phrase and sets its speech threshold 8 dB above that floor. `silence_threshold_db` is used until calibration completes.
- Media transport commands target whichever application currently owns the macOS media session. They do not choose a playlist when no media session exists. Use `media launch` to open YouTube Music first.
- The app is ad-hoc signed with a stable identifier-only designated requirement. This avoids a paid Apple developer account and should preserve Accessibility approval across local rebuilds. It is appropriate for this private local tool, but weaker than certificate-backed signing because another local app using the same bundle identifier could satisfy the requirement.
