---
description: "Safety constraints for parallel multi-agent, multi-model distributed task execution. Prevents git conflicts, session-artifact corruption, and duplicate-artifact creation when multiple agents operate simultaneously."
alwaysApply: true
---

## Parallel Execution Safety

When multiple agents (any combination of orchestrator + CLI executors) operate
on the same project simultaneously, the following constraints are
non-negotiable. Drop this file into a participating repo's governance directory
(e.g. `docs/ai/rules/parallel-execution/RULE.md`, symlinked from `.claude/rules`).

### 1. Branch Isolation (Critical)
Every parallel task MUST execute on its own git branch.
- The orchestrator assigns branches before dispatch.
- Branch naming: `task/{short-description}` (describes the WORK, not the tool).
- Agents MUST NOT modify files on a branch another agent is actively using.
- To read latest state, read from `main`/`develop` — never another agent's task branch.

**Exception:** if only ONE agent is active, it may work on the current branch without isolation.

### 2. Workspace Claims (Critical)
Before dispatching parallel tasks, the orchestrator MUST update `.forge/manifest.yaml`
to declare, per task: the agent, its branch, and the files/directories it claims.
Agents MUST NOT modify files outside their declared claims unless the file is
explicitly marked "shared-append" or is a build artifact in a temp/output dir.
If an agent needs an unclaimed file: stop, record the need in its agent-local
status area, and wait for the orchestrator to update the manifest.

### 3. Shared Artifact Serialization (Critical)
These files are NEVER written directly by parallel agents (adjust to your repo):
- `docs/ai/SESSION_CONTEXT_BUNDLE.md`, `SESSION_RESUME.md`, `CURRENT_FOCUS.md`,
  `SESSION_COMPLETION_SUMMARY.md`, `DECISIONS.md`, `AGENT_SCRATCH_NOTES.md`

Instead: agents write to their **agent-local area** `.forge/agents/{task-id}/`
(`notes.md`, `decisions.md`, `status.json`). The orchestrator merges these into
canonical files during reconciliation.

### 4. Manifest Is Source of Truth
`.forge/manifest.yaml` is written ONLY by the orchestrator, read by agents at
startup. Agents MUST NOT modify it. It tracks active tasks, branches, claims,
status, and completion state.

### 5. Pre-Dispatch Conflict Check
Before assigning a new parallel task, verify: (a) no file overlap between the new
task's claims and existing active claims, (b) no branch-name collision, (c) the
target branch exists and is clean (or will be created). On overlap: serialize the
tasks, redesign boundaries, or declare an explicit merge strategy.

### 6. Reconciliation Required
After parallel tasks complete, the orchestrator MUST review diffs, merge in
dependency order, resolve conflicts (or surface to human), consolidate
agent-local artifacts into canonical files, regenerate the session bundle, and
clean up the manifest. See the `reconcile-parallel-work` skill.

### When This Rule Applies
ACTIVE whenever more than one agent/tool executes work simultaneously, or the
orchestrator dispatches a task while another is still running.
INACTIVE (standard single-agent workflow) when only one agent works at a time
and tasks are fully sequential.

### Consequences of Violation
Git conflicts, lost work, stale context, build failures from interleaved edits,
and session-state corruption that poisons the next session's start.
