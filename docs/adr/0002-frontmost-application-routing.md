# ADR 0002: Commands route through the frontmost supported application

## Status

Accepted

## Decision

Prompt dictation and application-scoped commands bind to the supported application that is frontmost when the interaction begins. The supported targets are Ghostty, ChatGPT, and Chrome.

A command is rejected if its captured target is no longer frontmost when it would inject text or a keystroke. Explicit application-focus commands are the exception: they select their named target before running. Positional focus commands use the captured frontmost target. `focus one` through `focus eight` may run directly from idle; other commands require the normal wake interaction.

## Consequences

- Dictation and commands cannot silently move to an application selected after recording began.
- A user must keep the intended target frontmost through command injection.
- Global focus commands are the only commands permitted to change application focus.
- Idle positional focus remains a constrained shortcut rather than a general command channel.
