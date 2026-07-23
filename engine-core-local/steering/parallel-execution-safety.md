---
description: The non-negotiable safety framework for running 2+ agents in parallel — branch isolation, workspace claims, shared-artifact serialization, the manifest contract, pre-dispatch conflict checks, and the pre-flight checklist. Load before dispatching any parallel or overnight run.
alwaysApply: false
---

# Parallel Execution Safety

Load this **before** queueing more than one task at a time, or dispatching a task
while another is still running. These constraints prevent git conflicts, lost
work, and session-state corruption. The canonical rule ships in
`assets/governance/parallel-execution.rule.md` — install it into each
participating repo.

---

## The six rules

### 1. Branch isolation (critical)
Every parallel task runs on its own `task/{short-description}` branch (name the
WORK, not the tool). Agents never touch another agent's active branch; to read
latest state they read `main`/`develop`. *Exception:* a lone sequential agent may
work on the current branch.

### 2. Workspace claims (critical)
Before dispatch, declare in `.forge/manifest.yaml` — per task — the agent, its
branch, and the exact files/dirs it will modify. Agents modify **only** their
declared claims (plus explicit shared-append files and temp/output build
artifacts). Need an unclaimed file? Stop, record it in the agent-local status
area, wait for the orchestrator to update the manifest.

### 3. Shared-artifact serialization (critical)
Session-state files are **never** written by parallel agents. Instead each agent
writes to its **agent-local area** `.forge/agents/{task-id}/` (`notes.md`,
`decisions.md`, `status.json`), and the orchestrator merges them during
reconciliation. Typical protected files:
`SESSION_CONTEXT_BUNDLE.md`, `SESSION_RESUME.md`, `CURRENT_FOCUS.md`,
`SESSION_COMPLETION_SUMMARY.md`, `DECISIONS.md`, `AGENT_SCRATCH_NOTES.md`.

### 4. Manifest is source of truth
`.forge/manifest.yaml` is **write-only for the orchestrator, read-only for
executors.** Executors read it at startup to learn their boundaries; they must not
modify it.

### 5. Pre-dispatch conflict check
Before assigning a new parallel task, verify: no file overlap with any active
claim, no branch-name collision, and the target branch exists/clean (or will be
created). On overlap: serialize the tasks, redesign the boundaries, or declare an
explicit merge strategy.

### 6. Reconciliation required
After parallel completion, run the `reconcile-parallel-work` procedure — review
diffs, merge in dependency order, consolidate agent-local artifacts, regenerate
the session bundle, and clean the manifest. See `reconciliation.md`.

---

## The manifest contract

```yaml
# .forge/manifest.yaml — orchestrator writes, executors read.
version: "1.0"
last_updated: "2026-01-01T00:00:00Z"
updated_by: "orchestrator"

active_tasks:
  - id: "implement-build-adapter"
    branch: "task/build-adapter"
    agent: "claude-code-cli"
    claims:
      - "adapters/build/"
      - "package.json"
    status: "dispatched"        # queued|dispatched|running|completed|failed
    dispatched_at: "2026-01-01T00:05:00Z"
  - id: "implement-test-adapter"
    branch: "task/test-adapter"
    agent: "claude-code-cli"
    claims:
      - "adapters/test/"
    status: "dispatched"
    dispatched_at: "2026-01-01T00:05:30Z"

pending_reconciliation: []      # branches awaiting merge, in dependency order
```

Task prompts for parallel work must **restate their claim** and include the branch
instruction and a *Do NOT modify* list — the executor can't read your intent, only
the prompt (it does not parse the manifest itself).

---

## Pre-dispatch checklist (per task)

- [ ] Task prompt includes an explicit **branch** instruction (`task/{name}`)
- [ ] Manifest updated with this task's **claims**
- [ ] **No overlap** between these claims and any active task's claims
- [ ] **No branch-name collision**
- [ ] Prompt includes a **Do NOT modify** list covering shared session artifacts
- [ ] If it must touch shared files (rare), it is **sequenced** after its deps, not parallel

If any box is unchecked, do not queue the task in parallel — serialize it instead.

---

## When the rule is active vs inactive

- **ACTIVE** — 2+ agents/tools executing simultaneously, or dispatching while a
  `.running` task exists.
- **INACTIVE** — a single agent at a time, fully sequential (one finishes before
  the next starts). Standard single-agent workflow applies; branch isolation is
  optional.

## Consequences of skipping this
Manual merge-conflict cleanup (wastes the human's time — the one resource we
optimize for), overwritten work, stale context driving wrong decisions, build
failures from interleaved edits, and corrupted session state that poisons the next
session's start.
