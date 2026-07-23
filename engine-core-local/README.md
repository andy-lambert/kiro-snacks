# Engine Core Local — Kiro Power

A [Kiro Power](https://kiro.dev/docs/powers/) that turns a developer workstation
into a self-coordinating **multi-agent, multi-model task-execution pipeline**. One
tool orchestrates (reasoning, decomposition, tracking); local AI CLIs
(Claude Code, Codex, Kiro CLI, …) execute headless — with branch isolation,
parallel-execution safety, and automatic reconciliation.

> Core principle: **the orchestrator thinks, executors implement.** Coordination is
> just files on disk + git conventions — no servers, queues, or databases.

This is a **Knowledge Base Power** (no MCP server). All capability is delivered
through `POWER.md`, on-demand steering files, and ready-to-use asset templates.

## What Kiro gets when this power activates

- **Provision** the `~/.forge-bridge/` pipeline (cross-platform: macOS launchd /
  Linux systemd).
- **Route & dispatch** work to the cheapest capable executor via a file queue.
- **Run parallel/overnight batches** safely (branches, workspace claims, manifest).
- **Reconcile** parallel branches back into canonical state.
- **Operate & troubleshoot** a live bridge (health, cost, cleanup, known issues).

## Layout

```
engine-core-local/
├── POWER.md                       # metadata + onboarding + steering map (entry point)
├── README.md
├── steering/                      # loaded on-demand, one domain each
│   ├── provisioning.md
│   ├── dispatch-and-routing.md
│   ├── executors.md
│   ├── parallel-execution-safety.md
│   ├── reconciliation.md
│   ├── agents-commands-hooks.md
│   └── operations-and-troubleshooting.md
└── assets/                        # ready-to-write templates
    ├── forge-bridge/              # lib-common.sh, dispatch-{claude,codex,kiro}.sh,
    │                              #   watcher.sh, config/manifest examples
    ├── daemon/                    # launchd plist + systemd unit templates
    ├── claude/                    # subagents, slash commands, hook settings.json
    └── governance/                # parallel-execution rule + reconcile skill
```

## Supported executors

| Executor | Task file | Headless invocation |
|---|---|---|
| Claude Code CLI | `{id}.task.md` | `claude -p … --output-format json` |
| Codex CLI | `{id}.codex.task.md` | `codex exec --full-auto` |
| Kiro CLI | `{id}.kiro.task.md` | `kiro chat --no-interactive --trust-all-tools` (auth via `KIRO_API_KEY`) |

New executors are added with one dispatch script + a file-extension route — see
`steering/executors.md`.

## Install

**From a local folder:** Kiro → Powers panel → **Add Custom Power** →
**Import power from a folder** → select this directory.

**From GitHub:** push this directory to a public repo (with `POWER.md` at the
root), then Powers panel → **Add Custom Power** → **Import power from GitHub**.

Then say something like *"set up distributed task orchestration"* or *"dispatch
these tasks to the forge bridge"* and the power activates on its keywords.

## Requirements

- A queue watcher: `fswatch` (macOS/Linux) **or** `inotifywait` (Linux).
- `jq` and `flock` recommended (the scripts degrade gracefully without them).
- At least one executor CLI installed and authenticated.

## Credits

Distills the *Engine Core Local — Multi-Agent Orchestration Architecture* and its
agent/rule/skill kit into a portable, reusable Kiro Power. Scripts are generalized
(no hardcoded machine paths) and cross-platform.
