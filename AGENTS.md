## Agent skills

### Issue tracker

Tasks, issues, and PRDs are tracked with the Beans CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default triage-role vocabulary as Beans tags. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository. See `docs/agents/domain.md`.

## macOS Accessibility permissions

Do not repeatedly launch an application while waiting for the user to grant
Accessibility permission. Each launch can create another prompt, and approving
one prompt does not necessarily approve a different code identity.

When Accessibility permission is required:

1. Stop every running instance of the application and its helper processes.
2. Ask the user to grant permission, then wait for explicit confirmation before
   launching the application again.
3. If the application was rebuilt, reinstalled, or re-signed, remove only that
   application's stale Accessibility approval before presenting the final
   permission request. Do not reset unrelated privacy permissions.
4. Launch the final, unchanged build once. Do not rebuild, reinstall, re-sign,
   or launch it again while its permission request is pending.
5. After the user confirms approval, launch once if the prior process exited,
   then verify that the application and its helpers remain running.

If macOS keeps prompting even though the switch is on, stop launching the
application. Inspect the TCC logs and compare the approved and current code
identities. Treat a mismatched identity as a stale approval, not as a reason to
ask the user to toggle the switch repeatedly.
