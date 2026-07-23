---
description: Reference for each forge-bridge executor (Claude Code, Codex, Kiro CLI) — how its dispatch script works, the file-extension routing convention, headless invocation and auth, and how to add a brand-new executor. Load when configuring, debugging, or extending executors.
alwaysApply: false
---

# Executors

An **executor** is any CLI that can accept a task prompt and produce output. The
forge-bridge routes to executors purely by **file extension**, and each executor
has one thin dispatch script that sources `lib-common.sh`.

---

## File-extension routing

| Task file pattern | Dispatcher | Executor | Notes |
|---|---|---|---|
| `{id}.task.md` | `dispatch-claude.sh` | Claude Code CLI | The generic pattern — matched **last** |
| `{id}.codex.task.md` | `dispatch-codex.sh` | Codex CLI | |
| `{id}.kiro.task.md` | `dispatch-kiro.sh` | Kiro CLI | |

`watcher.sh` tests the specific patterns (`*.codex.task.md`, `*.kiro.task.md`)
**before** the generic `*.task.md`, and each dispatcher additionally filters the
generic glob so a `.codex.task.md` never falls through to Claude:

```bash
ls -tr "$QUEUE_DIR"/*.task.md | grep -Ev '\.(codex|kiro)\.task\.md$'
```

Each executor has its **own** lock file (`.dispatch-claude.lock`,
`.dispatch-codex.lock`, `.dispatch-kiro.lock`), so executors run concurrently
while each executor's own tasks stay serialized (FIFO).

---

## Common dispatch lifecycle

Every dispatcher follows the same shape (via `lib-common.sh`):

1. `acquire_lock` — take the executor's lock or exit 0 (safe re-entry from rapid
   watcher triggers).
2. Resolve the CLI binary with `command -v`; if missing, log and exit 0.
3. Pick the oldest matching task (`ls -tr … | head -1`).
4. `parse_frontmatter` — read `project-dir`, strip the frontmatter from the body.
5. `resolve_project_dir` — map the key to an absolute path via the registry; fail
   fast with `invalid project-dir` if unknown/missing.
6. Move `queue/{id}.<ext>.task.md` → `queue/{id}.<ext>.running`.
7. `cd` into the resolved working dir and invoke the CLI headless.
8. Capture output to `artifacts/`, write `status/{id}.status`, remove `.running`,
   log to `dispatch.log`, and fire a desktop `notify`.

---

## Claude Code CLI — `dispatch-claude.sh`

- **Invocation:** `claude -p "$PROMPT" --output-format json --allowedTools "…" --max-budget-usd 1.00 < /dev/null`
- **Tool allowlist:** `Read,Write,Edit,Bash,Grep,Glob,WebFetch,WebSearch,Agent`
  (exact tool names — not `GrepTool`/`GlobTool`).
- **Output:** raw JSON → `{id}.result.json`; `jq -r '.result'` → `{id}.result.md`;
  `session_id` saved to `{id}.session` for `--resume` follow-ups.
- **Budget:** `--max-budget-usd 1.00` default; the governance system prompt costs
  ~$0.05 to cache alone, so $1.00 is the practical minimum. Override with
  `FORGE_CLAUDE_MAX_BUDGET_USD`.
- **Governance:** auto-discovers `CLAUDE.md` from the working directory — the
  reason `project-dir` routing (not `cd` in the prompt) matters.
- **`< /dev/null`** prevents headless stdin-wait hangs.
- **Sweet spot:** governed multi-file implementation, build/test/deploy, git ops.

## Codex CLI — `dispatch-codex.sh`

- **Invocation:** `codex exec --full-auto "$PROMPT" < /dev/null` (single
  non-interactive turn; `--full-auto` grants tool use).
- **Output:** plain text with ANSI stripped (`sed`) → `{id}.result.md`; stderr →
  `{id}.stderr.log`; copied to `{id}.error.log` on failure.
- **No** JSON mode and **no** per-task budget flag.
- **Sweet spot:** focused single-scope fixes and token-efficient terminal work.
- **Caution:** GPT-family models can expand scope — always give an explicit
  *Do NOT modify* list in the prompt.

## Kiro CLI — `dispatch-kiro.sh`

- **Invocation:** `kiro chat --no-interactive --trust-all-tools "$PROMPT"`
  (binary is `kiro` in CLI 2.0+, `kiro-cli` on older builds — the script tries
  both).
- **Auth (headless):** export `KIRO_API_KEY` in the environment. For unattended
  daemon runs, set it in the launchd plist / systemd unit (both templates have a
  commented slot). See https://kiro.dev/docs/cli/headless/.
- **Output:** plain text with ANSI stripped → `{id}.result.md`; no JSON/budget
  flags.
- **Sweet spot:** AWS/resource queries, research (web + codebase), multi-stage
  analysis, and cross-session knowledge retrieval.

---

## Adding a new executor

The partner model is generic — any CLI that takes a prompt and prints output can
join. To add executor `foo` (candidate CLIs: other agentic terminals, e.g.
`auggie`):

1. **Choose an extension:** `{id}.foo.task.md`.
2. **Copy a dispatcher** — start from `dispatch-kiro.sh` (plain-text executors) or
   `dispatch-claude.sh` (JSON output). Change: the lock file name
   (`.dispatch-foo.lock`), the binary resolution, the glob (`*.foo.task.md`), the
   `.running` suffix, and the invocation line.
3. **Register the route** in `watcher.sh` — add a `*.foo.task.md)` case **above**
   the generic `*.task.md)` case so it's matched first.
4. **Keep it plain-text** unless the CLI emits structured JSON you want to parse.
5. **Restart the daemon** so the watcher picks up the new routing.
6. **Smoke test** with a trivial `{id}.foo.task.md`.

Checklist for a correct new dispatcher:
- [ ] Sources `lib-common.sh` and calls `acquire_lock` with a **unique** lock file
- [ ] Resolves its binary with `command -v`; exits 0 if absent
- [ ] Uses `parse_frontmatter` + `resolve_project_dir` (respects `project-dir`)
- [ ] Writes `{id}.result.md` and `status/{id}.status`; removes its `.running`
- [ ] Logs to `dispatch.log` and calls `notify`
- [ ] Added to `watcher.sh` routing **before** the generic case

---

## Capability matrix

| Capability | Claude Code | Codex | Kiro CLI |
|---|---|---|---|
| Multi-file implementation | Excellent | Good (single-scope) | Good |
| Build / test / deploy | Excellent | Good | Via shell |
| Git operations | Native (branch/commit/push) | Via shell | Via shell |
| Repo governance auto-discovery | `CLAUDE.md` | `AGENTS.md` | `AGENTS.md` |
| Structured resource/API tooling | Via Bash | Via Bash | Native, typed |
| Web search / fetch | Yes | Yes | Yes |
| Cross-session knowledge | No | No | Yes (semantic KB) |
| Per-task budget cap | Yes (`--max-budget-usd`) | No | No |
| Structured JSON result | Yes | No | No |
| Headless auth | enterprise SSO / API key | API key | `KIRO_API_KEY` |
