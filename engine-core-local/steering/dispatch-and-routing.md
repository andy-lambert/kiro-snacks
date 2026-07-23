---
description: How to route work to the right tool, compose self-contained task prompts, dispatch tasks to the forge-bridge queue, monitor execution, and triage results. Load when the operator wants to dispatch work or decide which tool should handle a task.
alwaysApply: false
---

# Dispatch & Routing

This is the day-to-day operating manual for the orchestrator: decide where work
goes, write a task the cold-start executor can act on, drop it in the queue,
watch it, and judge the result.

---

## 1. Routing — send each task to the cheapest capable tool

Route by **capability**, not habit. Only route to executors that are installed
and authenticated (confirmed during onboarding).

| Keep with the ORCHESTRATOR (you) | Dispatch to an EXECUTOR |
|---|---|
| Architectural reasoning, trade-offs, design decisions | Multi-file implementation |
| Task decomposition & prompt composition | Build / test / deploy cycles |
| Synthesizing large context across many docs | Git operations (branch, commit, push, PR) |
| Code review with architectural awareness | Codebase search → action sequences |
| Progress tracking, escalation, reconciliation | Any headless autonomous execution |

### Executor selection

| Task shape | Best executor | Why |
|---|---|---|
| Multi-file feature, refactor spanning interdependent files, git-heavy work under repo governance | **Claude Code CLI** (`.task.md`) | Governance auto-discovery + bash + budget cap in one session |
| Focused single-scope fix (one bug, one targeted refactor, test generation), token-sensitive | **Codex CLI** (`.codex.task.md`) | Efficient terminal agent; no per-task budget overhead |
| AWS resource queries, research (web + codebase), multi-stage analysis, cross-session knowledge | **Kiro CLI** (`.kiro.task.md`) | Native structured tooling + web + persistent knowledge |

Rules of thumb:
- **Answer matters more than code changes** → Kiro CLI.
- **Tight, single-file change where scope creep is a risk** → Codex CLI, and always
  include an explicit *Do NOT modify* list (GPT-family models can over-reach).
- **Interdependent multi-file change needing governance + git** → Claude Code CLI.
- **Needs deep reasoning / real-time steering** → keep it yourself; don't dispatch.

> Model names and benchmark rankings shift constantly. Choose by the capability
> columns above, not by a specific version number.

---

## 2. Compose a self-contained task prompt

The executor starts **cold**: no session memory, no shared context. Every prompt
must stand alone. Include all six elements:

1. **Objective** — precisely what to accomplish, and why.
2. **File paths** — exact files to read, create, or modify.
3. **Constraints** — architectural rules and anti-patterns to avoid.
4. **Output spec** — what to produce, in what format, where to write it.
5. **Branch** — which branch to work on (for parallel/isolated work).
6. **Scope boundary** — an explicit *Do NOT modify* list.

### Template

```markdown
---
project-dir: infra
---
## Task: {descriptive title}

**Objective:** {1-2 sentences — what and why}

**Context:**
- Branch: {task/name or main}
- Key files to read: {paths}

**Instructions:**
1. {step}
2. {step}

**Constraints:**
- {constraint}

**Output:**
- Create/modify: {paths}
- Do NOT modify: {protected files/dirs}

**On completion:** Summarize what changed, which files, and any issues.
```

- The `project-dir` value is a **key from `~/.forge-bridge/config.yaml`**, not a
  path. Omit the frontmatter entirely to use `default_project`.
- **Never** instruct the agent to `cd` into another repo — use `project-dir`
  instead so governance discovery, relative paths, and git all resolve correctly.

### Anti-patterns
- Vague objective ("clean up the code") → the agent wanders.
- "Use the approach we discussed" → the executor has no memory; restate it.
- Unbounded scope ("fix all the issues") → burns budget; scope to files/concerns.

---

## 3. Dispatch

### Single task
Write the file into the queue; the watcher does the rest.
```bash
cat > ~/.forge-bridge/queue/my-task.task.md <<'EOF'
## Task: ...
EOF
```

### Sequential tasks — make ordering deterministic
Dispatch is FIFO by filename (oldest first). Rapid writes can land out of order,
so **prefix with sequence numbers**:
```
~/.forge-bridge/queue/01-scaffold.task.md
~/.forge-bridge/queue/02-implement.task.md
~/.forge-bridge/queue/03-test.task.md
```
A brief pause between writes further stabilizes ordering.

### Parallel tasks
Only after satisfying the safety rules — update `.forge/manifest.yaml` with
non-overlapping claims and give each task its own `task/{name}` branch. See
`parallel-execution-safety.md` before queueing anything in parallel.

### Choosing the executor
The **file extension** picks the dispatcher: `.task.md` → Claude, `.codex.task.md`
→ Codex, `.kiro.task.md` → Kiro. See `executors.md`.

---

## 4. Monitor

```bash
tail -f ~/.forge-bridge/status/dispatch.log     # live timeline
ls ~/.forge-bridge/queue/*.running 2>/dev/null  # what's executing now
cat ~/.forge-bridge/status/*.status             # completed/failed per task
```

Budget note (Claude Code): the governance system prompt alone can cost ~$0.05 to
cache, so the minimum useful `--max-budget-usd` is `1.00`. Override per-run with
`export FORGE_CLAUDE_MAX_BUDGET_USD=3.00` before a large task (the daemon must see
the env var — set it in the daemon environment for unattended runs).

---

## 5. Review & triage

```bash
cat ~/.forge-bridge/artifacts/{id}.result.md                 # human-readable result
jq '.cost_usd, .num_turns, .session_id' \
   ~/.forge-bridge/artifacts/{id}.result.json                # Claude metadata
cat ~/.forge-bridge/artifacts/{id}.error.json                # on failure
```

**Verify before declaring success.** A `completed` status only means the process
exited 0. Read the result and the actual diff, and confirm the task's stated
output exists and is correct.

| Outcome | Action |
|---|---|
| Clean, output correct | Accept → next task or reconcile |
| Minor issues | Compose a targeted fix task and dispatch |
| Failed (exit/budget) | Inspect `error.json`; adjust prompt/budget; re-dispatch |
| Partial | Extract useful work; write a continuation task with an explicit resume point |
| Scope creep | Discard; rewrite with a tighter *Do NOT modify* list |

---

## 6. Workflow patterns

- **A — Orchestrator plans, CLI executes (primary):** decompose → compose
  self-contained prompts → queue → review → fix/follow-up → reconcile if parallel.
- **B — Orchestrator architects, human applies:** write a blueprint to
  `~/.forge-bridge/blueprints/` (via the `blueprint-writer` agent) for a human to
  apply interactively in an IDE.
- **C — Direct execution:** for small/fast/steered work, just do it yourself — the
  dispatch overhead isn't justified.
