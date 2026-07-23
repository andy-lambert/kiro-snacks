---
name: reconcile-parallel-work
description: "Merge parallel agent branches back into canonical project state and consolidate agent-local artifacts. Use after a parallel/overnight dispatch run completes."
---

# Reconcile Parallel Work

The 7-step procedure the orchestrator runs after parallel tasks finish. Drop
into a participating repo (e.g. `docs/ai/skills/reconcile-parallel-work/SKILL.md`,
symlinked from `.claude/skills`).

## 1. Review the manifest
Read `.forge/manifest.yaml`. Identify every branch in `pending_reconciliation`
and its `merge_order`. Confirm each task's status is `completed` (investigate any
`failed` entries before merging).

## 2. Review diffs per branch
For each branch, inspect the change set against the integration branch:
```bash
git diff develop...task/{branch} --stat
git diff develop...task/{branch}
```
Confirm each branch only touched files within its declared claims.

## 3. Merge in dependency order
Merge branches in ascending `merge_order` (tasks with no cross-dependencies
first). Prefer explicit, reviewable merges:
```bash
git checkout develop
git merge --no-ff task/{branch}
```
Resolve conflicts deterministically; surface anything ambiguous to the human.

## 4. Consolidate agent-local artifacts
Fold each `.forge/agents/{task-id}/` (`notes.md`, `decisions.md`, `status.json`)
into the canonical session files (DECISIONS.md, scratch notes, etc.). This is the
ONLY place shared session artifacts are written.

## 5. Update session artifacts
Regenerate the session bundle / focus / resume documents from the merged state so
the next session starts with correct context.

## 6. Clean up
Delete merged branches (`git branch -d task/{branch}`), archive the agent-local
dirs, and clear reconciled entries from the manifest (`active_tasks` and
`pending_reconciliation`).

## 7. Verify final state
Run the project's build/test on the merged result. Only report the run complete
once the merged state is green and the manifest is clean.
