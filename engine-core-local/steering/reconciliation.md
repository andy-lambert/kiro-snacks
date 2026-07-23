---
description: The seven-step procedure for merging parallel agent branches back into canonical project state and consolidating agent-local artifacts. Load after a parallel or overnight dispatch run, when branches are ready to integrate.
alwaysApply: false
---

# Reconciliation

After parallel tasks finish, the orchestrator must fold the branches and their
agent-local artifacts back into canonical state. This is rule #6 of the safety
framework and is **required** — an unreconciled run leaves the repo with orphaned
branches and a stale session bundle. The installable version ships in
`assets/governance/reconcile-parallel-work.skill.md`.

Reconciliation is **orchestrator-only** work. Do not dispatch it to an executor —
it needs cross-branch judgment and is the one place shared session files are
written.

---

## The seven steps

### 1. Review the manifest
Open `.forge/manifest.yaml`. List every entry in `pending_reconciliation` with its
`merge_order`. Confirm each corresponding task's `status` is `completed`.
Investigate any `failed` task before merging its branch — never merge a branch
whose task failed without understanding what it left behind.

### 2. Review diffs per branch
```bash
git fetch --all
git diff develop...task/{branch} --stat     # scope overview
git diff develop...task/{branch}            # full review
```
Confirm each branch touched **only** the files it claimed in the manifest. A
branch that strayed outside its claims is a safety violation — inspect closely and
consider discarding the out-of-claim changes.

### 3. Merge in dependency order
Merge ascending by `merge_order` (independent tasks first, dependents later):
```bash
git checkout develop
git merge --no-ff task/{branch} -m "reconcile: {task-id}"
```
`--no-ff` keeps each task's work as a reviewable unit. Resolve conflicts
deterministically; if a conflict is ambiguous or spans design decisions, **surface
it to the human** rather than guessing.

### 4. Consolidate agent-local artifacts
Each agent wrote to `.forge/agents/{task-id}/` (`notes.md`, `decisions.md`,
`status.json`). Fold these into the canonical session files (e.g. `DECISIONS.md`,
scratch notes). **This is the only place shared session artifacts are written** —
honoring rule #3.

### 5. Update session artifacts
Regenerate the session bundle / current-focus / resume documents from the merged
state so the next session starts with accurate context.

### 6. Clean up
```bash
git branch -d task/{branch}                 # delete merged branch
```
Archive the agent-local dirs (e.g. move `.forge/agents/{task-id}/` to
`.forge/agents/_archive/{date}/`), and clear the reconciled entries from both
`active_tasks` and `pending_reconciliation` in the manifest. Bump
`last_updated`.

### 7. Verify final state
Run the project's build/test on the merged result:
```bash
# e.g. npm test / pytest / make check — whatever the repo uses
```
Only report the run complete once the merged state is **green** and the manifest
is clean. A merge that builds is the success criterion — not the fact that
branches merged without a git conflict.

---

## Merge-order heuristics
- Foundational/scaffolding tasks (new files, shared configs) merge **first**.
- Tasks that only add isolated files (independent adapters, new modules) can merge
  in any relative order.
- Tasks that modify a file another task created must merge **after** it.
- If two branches both had to touch a genuinely shared file, that was a
  pre-dispatch conflict-check miss — resolve carefully and note it as a lesson.

## Common pitfalls
- **Skipping step 7** — "it merged cleanly" is not "it works." Always build/test.
- **Writing session artifacts before merging** — corrupts state if a later merge
  changes decisions. Consolidate only after all branches are in.
- **Deleting branches before verifying** — keep branches until the merged build is
  green, in case you need to re-examine or revert.
