---
description: Day-to-day operations for a running forge-bridge — starting a session, health checks, monitoring, cleanup/log rotation, cost tracking, the overnight-run playbook, and a catalog of known issues with fixes. Load when operating, maintaining, or debugging a live bridge.
alwaysApply: false
---

# Operations & Troubleshooting

For a bridge that already exists. Provisioning lives in `provisioning.md`; this is
about running it well and fixing it when it misbehaves.

---

## Start-of-session checklist

```bash
# 1. Watcher alive?
launchctl list | grep forge                      # macOS
systemctl --user is-active forge-bridge-watcher  # Linux

# 2. Queue clean? (no leftover tasks or orphaned .running markers)
ls -la ~/.forge-bridge/queue/

# 3. Recent history
tail -20 ~/.forge-bridge/status/dispatch.log

# 4. Executor auth (only those installed)
claude auth status ; echo "${KIRO_API_KEY:+KIRO_API_KEY set}"
```

If the watcher is down, (re)load it (see `provisioning.md` Step 4). If orphaned
`*.running` files exist, a prior dispatch crashed — remove the marker and check
`artifacts/` for partial output before re-queueing.

---

## Health check (run periodically / start of an unattended run)

```bash
# watcher process present
pgrep -fl watcher.sh || echo "WARN: watcher not running"
# stale running tasks (older than ~30 min ⇒ likely orphaned)
find ~/.forge-bridge/queue -name '*.running' -mmin +30 -print
# disk headroom for artifacts/logs
df -h ~ | tail -1
# dependency sanity
command -v fswatch inotifywait flock jq 2>/dev/null
```

Recommended: wire these into a `forge-health` alias or a periodic job before
launching a long batch.

---

## Live monitoring

```bash
tail -f ~/.forge-bridge/status/dispatch.log        # dispatch timeline
tail -f ~/.forge-bridge/status/events.jsonl        # session Stop events (hooks)
tail -f ~/.forge-bridge/status/tool-events.jsonl   # Bash tool events (hooks)
watch -n2 'ls ~/.forge-bridge/queue/*.running 2>/dev/null; echo ---; cat ~/.forge-bridge/status/*.status 2>/dev/null'
```

---

## Cost tracking (Claude Code)

Each Claude result JSON carries `cost_usd`. Aggregate a run:

```bash
# total across all current results
jq -s 'map(.cost_usd // 0) | add' ~/.forge-bridge/artifacts/*.result.json
# per-task, sorted
for f in ~/.forge-bridge/artifacts/*.result.json; do
  printf '%s\t%s\n' "$(basename "$f" .result.json)" "$(jq -r '.cost_usd // 0' "$f")"
done | sort -k2 -gr
```

Codex and Kiro don't emit structured cost; track those out of band.

---

## Cleanup & log rotation (after a run)

```bash
# archive artifacts
mkdir -p ~/.forge-bridge/artifacts/archive/$(date +%Y%m%d)
mv ~/.forge-bridge/artifacts/*.result.* ~/.forge-bridge/artifacts/archive/$(date +%Y%m%d)/ 2>/dev/null

# clear status/session markers
rm -f ~/.forge-bridge/status/*.status ~/.forge-bridge/status/*.session

# rotate the dispatch log
cp ~/.forge-bridge/status/dispatch.log ~/.forge-bridge/status/dispatch.log.$(date +%Y%m%d) 2>/dev/null
: > ~/.forge-bridge/status/dispatch.log
```

---

## Overnight / unattended run playbook

1. **Health check** passes (above); watcher confirmed alive.
2. **Auth is non-interactive**: `claude auth status` valid; `KIRO_API_KEY` exported
   in the **daemon** environment (not just your shell) for any Kiro tasks.
3. **Decompose** into self-contained tasks (`dispatch-and-routing.md`). Cold-start
   executors have zero memory — over-specify context.
4. **Deterministic order**: prefix sequential tasks `01-…`, `02-…`.
5. **Parallel? Satisfy the safety framework first** — branches, claims, manifest
   (`parallel-execution-safety.md`).
6. **Budget headroom** for Claude: the shared system prompt (~13K tokens) costs
   ~$0.05 to cache; a whole run of small tasks is typically a few dollars at the
   $1.00/task cap. Raise `FORGE_CLAUDE_MAX_BUDGET_USD` for big tasks.
7. **In the morning**: read every `*.result.md` and verify diffs; **reconcile** any
   parallel branches before declaring the run done.

> Reality check from a real 7-task overnight run: the tasks executed in ~7 minutes
> total, sequentially, under ~$7 all-in. But ordering was not strictly sequential
> because dispatch picks by filesystem timestamp — which is exactly why sequence-
> number prefixes matter.

---

## Emergency stop

```bash
pkill -f "claude -p"        # or: pkill -f "codex exec" / pkill -f "kiro chat"
rm -f ~/.forge-bridge/queue/*.running
launchctl unload ~/Library/LaunchAgents/com.forge.bridge-watcher.plist   # macOS
systemctl --user stop forge-bridge-watcher                               # Linux
```

---

## Known issues & fixes

| Symptom | Cause | Fix |
|---|---|---|
| `flock: command not found` (macOS) | macOS ships no `flock` | `brew install flock`; `lib-common.sh` also falls back to an `mkdir` lock automatically |
| `claude/kiro/codex: not found` in dispatch.log | CLI not on the **daemon's** minimal `PATH` | Add its dir to the daemon `PATH` (launchd plist `EnvironmentVariables.PATH` / systemd `Environment=PATH=…`); restart the daemon |
| "Credit balance too low" despite valid account | Stale `ANTHROPIC_API_KEY` in shell rc overriding SSO | Remove the stale export; `claude auth status` to confirm |
| Tasks run out of intended order | Dispatch picks by mtime; rapid writes collide | Prefix task IDs `01-`, `02-`; add a brief pause between writes |
| `--max-budget-usd 0.05` fails before any output | System-prompt cache alone (~$0.05) exceeds tiny budgets | Minimum practical budget is `$1.00` |
| `--allowedTools GrepTool,GlobTool` rejected | Wrong tool names | Use `Grep,Glob` (verify with `claude tools list`) |
| Edited a dispatch script but behavior unchanged | Daemon running with a stale environment | Restart the daemon (`unload`/`load` or `systemctl --user restart`) |
| Watcher fires but nothing dispatches | No `fswatch`/`inotifywait`, or CLI missing | Install a watcher backend; confirm the executor CLI resolves via `command -v` |
| `invalid project-dir` in status | `project-dir` key absent from `config.yaml`, or path doesn't exist | Add/fix the key under `projects:`; ensure the path exists |
| Kiro headless hangs / auth error unattended | `KIRO_API_KEY` not visible to the daemon | Set it in the daemon environment, not just your interactive shell |
| Result says `completed` but work looks wrong | Exit 0 ≠ correct output | Always read `result.md` and the diff; verify against the task's stated output before accepting |

---

## Design limits (by intent)
- **Per-dispatcher serialization** via `flock` — one task at a time per executor;
  different executors run concurrently. True intra-executor parallelism would need
  task-level (not queue-level) locking.
- **No inter-task memory** — every invocation is a cold start; chain results
  manually by embedding prior output into the next task's prompt.
- **Self-contained prompts only** — the pipeline does not compose prompts from
  prior results automatically.
- **Manual dependency ordering** — there is no task DAG; the orchestrator sequences
  tasks (sequence-number prefixes) or gates them via reconciliation.
