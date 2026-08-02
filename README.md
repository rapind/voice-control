# Voice Control Prototype

This is throwaway code answering one question: can one small macOS process reliably own the complete voice transaction without wrapping Codex or interfering with Ghostty's terminal rendering?

The daemon listens for a wake phrase, records until a submit phrase or silence, transcribes locally with Parakeet, strips the submit phrase, focuses the captured Ghostty session, pastes the prompt, and presses Return.

## Before running

1. Load Parakeet once in TypeWhisper. The prototype reuses the model files already stored in FluidAudio's shared cache. TypeWhisper does not need to remain open.
2. Leave the intended Codex tab active in Ghostty.

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

The app creates it with these defaults:

```toml
wake = ["ghostee", "ghostty", "ghostie", "ghosty", "ghost tea"]
submit = ["ghost it"]
cancel = ["ghost cancel"]

silence_seconds = 4
silence_threshold_db = -42
maximum_recording_seconds = 90

[commands]
new_tab = ["new tab", "open new tab"]
next_tab = ["next tab"]
previous_tab = ["previous tab", "prev tab"]
focus_tab_1 = ["focus tab 1", "tab 1"]
```

Save the file and the app applies valid changes within about one second. You do not need to rebuild or restart it. Invalid TOML leaves the last working configuration active and shows a config error in the menu.

Use another configuration file when launching if needed:

```bash
./run-prototype.sh --config "$HOME/path/to/config.toml"
```

On first launch, macOS asks for Microphone, Speech Recognition, and Accessibility permission. Accessibility is required only for focusing Ghostty and sending paste/Return.

The menu-bar item shows the current state and active control phrases. Use **Open Configuration** there to edit the TOML file. Quit it from that menu or press Control-C in the launching terminal.

## Ghostty commands

Ghostty is focused as soon as any configured wake phrase is recognized. Configured command aliases execute immediately from Apple Speech partials and do not require a submit phrase. The default commands are:

- `new tab`
- `focus tab 1` through `focus tab 9`
- `next tab`
- `previous tab`
- `focus Ghostty`

All other speech remains a normal Codex prompt and is transcribed by Parakeet after a configured submit phrase or the silence timeout.

Say a configured cancel phrase while recording to discard the prompt and return to wake listening. Nothing is transcribed, pasted, or submitted.

## Prototype limits

- It targets the currently frontmost Ghostty process when the wake phrase is detected. If another app is frontmost, it falls back to the running Ghostty app and its last active tab.
- The submit phrase is recognized by Apple Speech but the final prompt is transcribed by Parakeet. A badly mis-transcribed submit phrase can remain at the end of the prompt.
- Model downloading and Hugging Face authentication are deliberately out of scope. The prototype fails clearly when the shared cached model is missing.
- Silence detection uses a configurable RMS threshold, not a neural VAD.
- The app is ad-hoc signed with a stable identifier-only designated requirement. This avoids a paid Apple developer account and should preserve Accessibility approval across local rebuilds. It is appropriate for this private local tool, but weaker than certificate-backed signing because another local app using the same bundle identifier could satisfy the requirement.

Delete or replace this prototype after the interaction model has been tested.
