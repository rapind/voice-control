---
# voice-control-qqlk
title: Fix restart session interruption
status: scrapped
type: bug
priority: normal
created_at: 2026-08-16T15:59:39Z
updated_at: 2026-08-16T16:00:29Z
---

Investigate why the Ghostty `restart session` voice command launches OMP without visibly interrupting the active session.

- [ ] Reproduce and distinguish command recognition from Control-C delivery
- [ ] Fix the verified cause and add regression coverage
- [ ] Rebuild, install, and verify the restarted app

## Reasons for Scrapping

The restart workflow is no longer wanted. Keep separate interrupt and start commands instead.
