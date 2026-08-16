# Architecture Decision Records

Architecture Decision Records describe the current design constraints that should survive implementation churn. They are not release notes or a substitute for Git history.

- Add an ADR when a decision changes a system boundary, user interaction model, persistence format, or recovery behavior.
- Keep each record focused on one decision and describe the intended design in present tense.
- Update the existing record when its decision evolves. Git history preserves prior versions.
- Number records sequentially with a zero-padded prefix: `0001-short-decision-name.md`.

## Records

- [0001: Persistent wake listening recovers after audio interruption](0001-persistent-wake-listening.md)
- [0002: Commands route through the frontmost supported application](0002-frontmost-application-routing.md)
- [0003: Voice phrases are user configuration](0003-configured-voice-phrases.md)
