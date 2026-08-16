# ADR 0003: Voice phrases are user configuration

## Status

Accepted

## Decision

Voice phrases live in `~/.config/voice-control/config.toml`, not in application code. The configuration owns wake, submit, cancel, vocabulary, and per-application command phrase mappings. The daemon reloads a valid saved configuration without requiring a restart and retains the last valid configuration when a reload fails.

Each command belongs to an application mapping. Ghostty owns terminal and OMP session commands, including `start session`, `share session`, and `stop sharing`. ChatGPT and Chrome reject those Ghostty-only commands. Default phrase mappings are recognition hints and user-editable values, not fixed product vocabulary.

## Consequences

- Users can tune phrases for their pronunciation and speech recognition results without rebuilding the daemon.
- Command scope is validated during configuration loading, preventing unsupported application commands from entering the matcher.
- Documentation and generated default configuration must describe the same command keys and default phrases.
- Code changes must preserve configuration compatibility or provide an explicit migration.
