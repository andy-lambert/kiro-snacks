---
description: The in-repo executor kit each participating project needs — Claude Code subagents, slash commands, event-logging hooks, the parallel-execution rule, and the reconcile skill, plus the recommended .claude / .forge directory layout. Load when adding a project to the fleet or configuring its in-repo governance.
alwaysApply: false
---

# In-Repo Kit: Agents, Commands & Hooks

Any git project joins the fleet by adding a small, standard set of in-repo files.
No project-specific code is required. All templates ship under
`assets/claude/` and `assets/governance/`.

---

## Recommended layout

```
<repo>/
├── .claude/
│   ├── agents/          # Claude Code subagent definitions
│   │   ├── blueprint-writer.md
│   │   ├── build-runner.md
│   │   └── eds-validator.md
│   ├── commands/        # slash commands
│   │   ├── dispatch-task.md
│   │   └── forge-status.md
│   ├── settings.json    # event-logging hooks
│   ├── rules  -> ../docs/ai/rules     # POSIX symlink
│   └── skills -> ../docs/ai/skills    # POSIX symlink
├── .forge/
│   ├── manifest.yaml    # parallel-execution coordination (orchestrator-owned)
│   └── agents/          # agent-local scratch: {task-id}/{notes,decisions,status}
└── docs/ai/
    ├── rules/parallel-execution/RULE.md
    └── skills/reconcile-parallel-work/SKILL.md
```

> Use real **POSIX symlinks** for `.claude/rules` and `.claude/skills` — not macOS
> Finder alias files, which are not portable and don't work with the CLIs:
> ```bash
> ln -s ../docs/ai/rules  .claude/rules
> ln -s ../docs/ai/skills .claude/skills
> ```

---

## Subagents (`.claude/agents/`)

Each is YAML frontmatter (`name`, `description`, `tools`, `model`) + a system
prompt. The agent's `description` is what the orchestrator matches on when
deciding to delegate.

| Agent | Model | Tools | Purpose |
|---|---|---|---|
| `blueprint-writer` | opus | Read, Grep, Glob, Write | Produces implementation blueprints to `~/.forge-bridge/blueprints/` for IDE/composer execution (Pattern B) |
| `build-runner` | sonnet | Read, Bash, Edit, Write | Runs lint/test cycles, categorizes failures, proposes/apply fixes, never commits directly |
| `eds-validator` | sonnet | Read, Grep, Glob, Bash | Validates produced artifacts against project contracts/schemas; report-only |

Rename/retune these to your domain — the pattern (a planner, a build/test agent, a
validator) generalizes well. Give each a tight tool allowlist and a clear
output-file convention.

---

## Slash commands (`.claude/commands/`)

- **`dispatch-task`** — execute a task under repo governance and the
  parallel-execution rule, write results to the forge-bridge artifacts, and
  recommend (but not perform) follow-ups. `$ARGUMENTS` carries the task body.
- **`forge-status`** — one comprehensive report: git state, queue + orphaned
  `.running` markers, recent dispatch log, per-task status, manifest claims +
  `pending_reconciliation`, and watcher health.

---

## Event-logging hooks (`.claude/settings.json`)

Two hooks give the orchestrator passive visibility into executor activity — no
polling required:

- **`Stop`** → appends `{"event":"stop","ts":"…"}` to
  `~/.forge-bridge/status/events.jsonl` when a Claude Code session ends.
- **`PostToolUse`** (matcher `Bash`) → appends `{"event":"bash","ts":"…"}` to
  `~/.forge-bridge/status/tool-events.jsonl` after each Bash invocation.

The orchestrator tails those JSONL files to watch progress live. Extend with more
matchers (e.g. `Write`, `Edit`) if you want finer-grained telemetry.

---

## `.forge/` coordination

- **`manifest.yaml`** — the parallel-execution contract; orchestrator-owned. See
  `parallel-execution-safety.md`.
- **`agents/{task-id}/`** — each executor's private scratch space (`notes.md`,
  `decisions.md`, `status.json`). Parallel agents write here **instead of** the
  shared session files; the orchestrator consolidates during reconciliation.

---

## Governance rule & skill (`docs/ai/`)

- `rules/parallel-execution/RULE.md` — from
  `assets/governance/parallel-execution.rule.md` (`alwaysApply: true`, so it's
  always in force). Amend your existing "STOP protocol"/artifact-creation rules to
  first check `.forge/manifest.yaml` for active claims.
- `skills/reconcile-parallel-work/SKILL.md` — from
  `assets/governance/reconcile-parallel-work.skill.md`; the merge procedure.

---

## Onboarding a new project — checklist

- [ ] Copy `.claude/agents/*`, `.claude/commands/*`, `.claude/settings.json`
- [ ] Create POSIX symlinks `.claude/rules` and `.claude/skills`
- [ ] Install `docs/ai/rules/parallel-execution/RULE.md` and
      `docs/ai/skills/reconcile-parallel-work/SKILL.md`
- [ ] `mkdir -p .forge/agents` and add `.forge/manifest.yaml` (empty `active_tasks`)
- [ ] Register the repo in `~/.forge-bridge/config.yaml` under `projects:`
- [ ] Smoke-test a dispatch with `project-dir:` pointing at the new key
