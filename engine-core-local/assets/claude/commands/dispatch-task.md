---
description: Execute a queued task file under repo governance and write results to the forge-bridge.
---
Execute the task described below following this repository's governance
(CLAUDE.md / AGENTS.md) and the parallel-execution rule.

Task:
$ARGUMENTS

Requirements:
1. Work only within the files/directories the task authorizes. Respect any
   "Do NOT modify" list.
2. If the task specifies a branch, create/checkout it before making changes.
3. On completion, write a concise summary of what changed (files, rationale,
   any follow-ups) to ~/.forge-bridge/artifacts/{task-id}.result.md
4. Recommend sensible follow-up work, but do not perform it unasked.
