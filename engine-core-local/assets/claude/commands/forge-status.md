---
description: Produce a comprehensive Engine Core Local status report.
---
Produce a status report covering:

1. **Git state** — current branch, uncommitted changes, recent commits.
2. **Queue** — pending task files and any orphaned `*.running` markers:
   `ls -la ~/.forge-bridge/queue/`
3. **Recent dispatch history** — `tail -20 ~/.forge-bridge/status/dispatch.log`
4. **Per-task status** — `cat ~/.forge-bridge/status/*.status`
5. **Manifest** — active claims and `pending_reconciliation` from
   `.forge/manifest.yaml` (if present).
6. **Watcher health** — is the daemon running? (launchctl / systemctl).

Summarize the session phase and flag anything that needs the operator's
attention (failures, stale running tasks, unreconciled branches).
