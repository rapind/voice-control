# Voice Control

Voice Control is a maintained private macOS tool for owning a complete voice transaction without wrapping OMP or interfering with the target application's rendering.

The daemon listens for a wake phrase, captures the frontmost window without changing focus, shows a live transcription while recording, finalizes that transcript, and presses Return. Dictation uses local Parakeet v3 through FluidAudio on every supported macOS version. Apple Speech handles wake phrases and commands.

## Architecture decisions

The current design constraints are recorded in [Architecture Decision Records](docs/adr/README.md).

## Before running

1. Load Parakeet v3 once in TypeWhisper. The tool reuses the model files already stored in FluidAudio's shared cache. TypeWhisper does not need to remain open.
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
wake = ["echo"]
submit = ["echo"]
cancel = ["zulu"]
vocabulary = ["bean"]

silence_threshold_db = -45
maximum_recording_seconds = 360
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

`vocabulary` lists words and short phrases to bias Apple Speech toward when recognizing wake phrases and commands. It does not affect Parakeet dictation or replace recognized words.

The wake phrase plays its confirmation sound, then starts recording without changing focus. Dictation is bound to whichever window was frontmost when the wake phrase was recognized. Application-focus phrases, `focus ghost tee`, `focus chat`, and `focus chrome`, execute after a wake phrase.

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

All other speech remains a normal prompt. Rolling full-context Parakeet passes provide the live preview and may revise earlier words. A final Parakeet pass transcribes the complete recording for submission. Word and punctuation corrections are allowed, but an update that only returns an earlier prefix does not remove the displayed tail. This guard also applies to the final pass. Dictation does not select Apple's recognition engine based on the macOS version.

Silence never submits a prompt. Say a configured submit phrase to send. The six-minute recording limit prevents an abandoned recording from running forever.

The configured submit phrase triggers submission and remains in the transcript. The receiving agent treats the trailing phrase as control residue. Say a configured cancel phrase to clear the live preview, discard the recording, and return to wake listening without submitting.

## Operational limits

- You control input focus during dictation. Voice Control types into the focused control without checking that the captured application or field remains focused.
- Parakeet updates the preview after about every 1.5 seconds of additional audio and refines it with the final full-context pass at submission. Recognition time adds to the preview delay.
- Live text is typed as recognition updates arrive, without a field-readiness check or buffering until submission. Corrections read the captured application's current text selection, select the replacement range, and replace it in one operation. The range is acknowledged before replacement text is sent. Corrections require native access to the field's text and selection.
- Live edits do not wait for the resulting field value to match an expected string, because clients can expose placeholder text that disappears on insertion.
- Model downloading and Hugging Face authentication are deliberately out of scope. Dictation fails clearly when the shared cached Parakeet v3 model is missing. The FluidAudio dependency is pinned in `Package.swift`; the cached model files are reused without downloading updates.
- Apple voice processing can be enabled with `voice_processing = true`, but it is disabled by default because its call-oriented filtering weakens far-field dictation. When enabled, its multichannel device output is normalized to mono before recognition and recording.
- Silence detection measures the processed room noise while waiting for the wake phrase and sets its speech threshold 8 dB above that floor. `silence_threshold_db` is used until calibration completes.
- Media transport commands target whichever application currently owns the macOS media session. They do not choose a playlist when no media session exists. Use `media launch` to open YouTube Music first.
- The app is ad-hoc signed with a stable identifier-only designated requirement. This avoids a paid Apple developer account and should preserve Accessibility approval across local rebuilds. It is appropriate for this private local tool, but weaker than certificate-backed signing because another local app using the same bundle identifier could satisfy the requirement.
