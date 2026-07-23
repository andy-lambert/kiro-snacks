---
name: "engine-core-local"
displayName: "Engine Core Local"
description: "Orchestrate a fleet of local AI CLIs (Claude Code, Codex, Kiro CLI, and more) as a file-based, git-native, distributed task-execution pipeline. One tool reasons and composes tasks; others execute them in headless mode with branch isolation, parallel-execution safety, and automatic reconciliation. Turns any developer workstation into a self-coordinating multi-agent build system."
keywords:
  - "orchestration"
  - "multi-agent"
  - "multi agent"
  - "distributed tasks"
  - "task dispatch"
  - "dispatch"
  - "forge bridge"
  - "forge-bridge"
  - "engine core"
  - "parallel execution"
  - "overnight run"
  - "headless agent"
  - "claude code"
  - "codex cli"
  - "kiro cli"
  - "orchestrator"
  - "executor"
  - "task queue"
  - "reconciliation"
  - "branch isolation"
  - "agent fleet"
  - "task routing"
author: "Project Forge"
---

# Engine Core Local — Multi-Agent Orchestration

You are enhanced with **Engine Core Local**: a file-based, git-native pipeline that lets a single operator distribute work across many local AI CLIs at once. One tool acts as the **orchestrator** (strategic reasoning, task decomposition, progress tracking); the others act as **executors** (implementation, builds, deploys) running headless.

**Core principle:** *The orchestrator thinks, executors implement.* Every task flows to the cheapest capable tool. The optimization target is the operator's time — not token spend.

**Why it works:** coordination is just files on disk plus git conventions. No lock servers, message queues, databases, or new services — only a queue directory, a file watcher, per-executor dispatch scripts, and a git manifest. Any git project can join by adding a small in-repo kit and registering its path in `~/.forge-bridge/config.yaml`.

**Supported executors (extensible):**

| Executor | Task file pattern | Headless invocation | Sweet spot |
|---|---|---|---|
| Claude Code CLI | `{id}.task.md` | `claude -p … --output-format json` | Multi-file implementation, build/test/deploy, git ops, governed autonomous work |
| Codex CLI | `{id}.codex.task.md` | `codex exec …` | Focused single-scope fixes, token-efficient terminal-agent tasks |
| Kiro CLI | `{id}.kiro.task.md` | `kiro chat --no-interactive --trust-all-tools` | AWS queries, research, cross-session knowledge, multi-stage analysis |

New executors are added by dropping in one dispatch script and a file-extension pattern — see `steering/executors.md`.

---

## When This Power Activates

Use this power whenever the operator wants to:

- Set up, provision, or repair the forge-bridge dispatch infrastructure.
- Decompose a session into discrete tasks and **dispatch** them to CLI executors.
- Run **2+ independent tasks in parallel** with branch isolation.
- Run an **overnight** / unattended batch of autonomous tasks.
- **Reconcile** parallel branches back into canonical project state.
- Decide **which tool** should handle a given piece of work (routing).

Do **not** use it for a single, contained edit or a quick question you can answer directly — the dispatch pipeline is overhead you only want when work is parallelizable or long-running.

---

## Onboarding (run on first use)

Perform these checks before doing orchestration work. Report results to the operator, then proceed.

### Step 1 — Detect the platform and core dependencies

```bash
uname -s                       # Darwin (macOS) | Linux | (Windows: use WSL)
command -v fswatch  || echo "MISSING: fswatch"
command -v flock    || echo "MISSING: flock"     # macOS: brew install flock
command -v jq       || echo "MISSING: jq"
command -v git      || echo "MISSING: git"
```

- macOS: install with `brew install fswatch jq flock`.
- Linux: `flock` and `jq` ship in most distros; install `fswatch` (or the pipeline can fall back to `inotifywait`).
- **CRITICAL:** if `fswatch`/`inotifywait`, `flock`, and `jq` are unavailable, do not claim the watcher is running — surface the gap first.

### Step 2 — Detect available executors

Check which CLIs exist so routing recommendations are grounded in reality:

```bash
command -v claude   && echo "claude: $(command -v claude)"
command -v codex    && echo "codex:  $(command -v codex)"
command -v kiro     || command -v kiro-cli
```

Only route work to executors that are actually installed and authenticated.

### Step 3 — Check whether the bridge already exists

```bash
ls -la ~/.forge-bridge/ 2>/dev/null && echo "--- daemon ---"
# macOS:
launchctl list 2>/dev/null | grep forge
# Linux:
systemctl --user status forge-bridge-watcher 2>/dev/null | head -3
```

- If `~/.forge-bridge/` is **absent** → load `steering/provisioning.md` and provision from scratch.
- If it **exists** → load `steering/operations-and-troubleshooting.md`, verify the watcher is alive, and clear any stale `queue/*.running` markers before dispatching.

### Step 4 — Report readiness

Tell the operator: platform, which dependencies/executors are present, whether the bridge and watcher are up, and whether the queue is clean. Then confirm you are ready to accept task-decomposition instructions.

---

## When to Load Steering Files

This power is deep. Load only the file that matches the current sub-task to keep context lean.

| The operator wants to… | Load |
|---|---|
| Install / provision / repair the bridge, daemon, or project registry | `steering/provisioning.md` |
| Compose task prompts, dispatch work, decide routing, monitor & triage results | `steering/dispatch-and-routing.md` |
| Understand or configure a specific executor, or add a **new** executor | `steering/executors.md` |
| Run 2+ tasks in **parallel** safely (branches, claims, manifest) | `steering/parallel-execution-safety.md` |
| **Merge** parallel branches and consolidate session artifacts | `steering/reconciliation.md` |
| Add the in-repo executor kit (subagents, slash commands, event hooks) to a project | `steering/agents-commands-hooks.md` |
| Start/monitor a session, run health checks, clean up, track cost, or debug a known issue | `steering/operations-and-troubleshooting.md` |

Ready-to-write file templates (scripts, daemon units, agent/command definitions, governance rule + skill) live under `assets/` and are referenced from the steering files above.

---

## Mental Model (memorize this)

```
ORCHESTRATOR (you / Kiro / any high-context tool)
  │  writes  {id}.<ext>.task.md → ~/.forge-bridge/queue/
  │  reads   {id}.result.md      ← ~/.forge-bridge/artifacts/
  │  owns    .forge/manifest.yaml (workspace claims)
  ▼
FORGE BRIDGE  (queue + fswatch + daemon + flock-guarded dispatch scripts)
  │  extension → dispatcher → headless CLI (cold start, budget-capped)
  ▼
EXECUTOR CLI  (Claude Code / Codex / Kiro CLI / …) runs in the task's project dir
  │  produces result + status; fires a completion notification
  ▼
SHARED WORKSPACE  (registered git repos; branch-isolated when parallel)
```

- **Cold start:** every executor invocation has *no* memory of the session. Task prompts must be fully self-contained.
- **Serialized per dispatcher:** each dispatcher uses `flock`, so triggers are safely serialized; different executors can run concurrently.
- **Project routing:** a `project-dir:` key in the task's YAML frontmatter selects the target repo from the registry; the frontmatter is stripped before the prompt reaches the executor.

---

## Non-Negotiable Guardrails

Apply these on **every** orchestration action; the detailed rules live in `steering/parallel-execution-safety.md`.

1. **Branch isolation** — every parallel task runs on its own `task/{short-name}` branch. Single-agent sequential work may stay on the current branch.
2. **Workspace claims** — declare each task's file/directory ownership in `.forge/manifest.yaml` *before* dispatch; no overlapping claims.
3. **Shared-artifact serialization** — parallel agents never write shared session files directly; they write to `.forge/agents/{task-id}/` and the orchestrator merges during reconciliation.
4. **Manifest is source of truth** — write-only for the orchestrator, read-only for executors.
5. **Pre-dispatch conflict check** — verify no claim/branch overlap before queueing a task.
6. **Reconciliation required** — after any parallel run, review diffs, merge in dependency order, consolidate artifacts, regenerate the session bundle.

**Safety when in doubt:** never fabricate that a task "completed." A dispatcher exit code of 0 is *not* proof of success — read the `artifacts/{id}.result.md` and the produced diff, and verify against the task's stated output before reporting done.

---

## First Example (end-to-end smoke test)

```bash
# 1. Confirm the watcher is alive (see onboarding Step 3).
# 2. Drop a trivial task and let the pipeline run it:
cat > ~/.forge-bridge/queue/smoke-test.task.md <<'EOF'
Respond with only the text: FORGE BRIDGE OK
EOF
# 3. Wait ~15s, then verify:
cat ~/.forge-bridge/status/smoke-test.status        # -> completed
cat ~/.forge-bridge/artifacts/smoke-test.result.md  # -> FORGE BRIDGE OK
```

If the status is `completed` and the result contains `FORGE BRIDGE OK`, the bridge is working end-to-end. If not, load `steering/operations-and-troubleshooting.md`.
