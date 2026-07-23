---
description: Provision, repair, or uninstall the Engine Core Local forge-bridge from scratch — directories, dispatch scripts, project registry, and the watcher daemon (macOS launchd or Linux systemd). Load when the operator wants to set up or fix the bridge infrastructure.
alwaysApply: false
---

# Provisioning the Forge Bridge

Goal: stand up `~/.forge-bridge/` with working dispatch scripts, a project
registry, and a persistent watcher daemon — portable across macOS and Linux.
The `assets/` bundled with this power are the source of truth for every file
you write; copy them out rather than retyping from memory.

> **Prefer the bundled assets.** Each file below already exists under this
> power's `assets/` directory. Read the asset, then write it to the target path.
> The scripts are engineered to be portable (no hardcoded `/opt/homebrew` or
> `/Users/<name>` paths) — do not "simplify" them back to hardcoded paths.

---

## Step 0 — Detect platform & dependencies

```bash
uname -s   # Darwin | Linux
command -v fswatch inotifywait 2>/dev/null    # need at least one
command -v flock jq git 2>/dev/null
```

Install what's missing:

| Platform | Command |
|---|---|
| macOS (Homebrew) | `brew install fswatch jq flock` |
| Debian/Ubuntu | `sudo apt-get install -y inotify-tools jq` (flock ships in `util-linux`) |
| Fedora/RHEL | `sudo dnf install -y inotify-tools jq util-linux` |

`flock` and `jq` are strongly recommended but the pipeline degrades gracefully:
`lib-common.sh` falls back to an atomic `mkdir` lock if `flock` is absent, and
the Claude dispatcher copies raw JSON if `jq` is missing. A queue watcher needs
**either** `fswatch` **or** `inotifywait`.

---

## Step 1 — Create the directory structure

```bash
mkdir -p ~/.forge-bridge/{queue,status,context,artifacts,blueprints}
```

```
~/.forge-bridge/
├── queue/        # task files: {id}.<ext>.task.md -> .running -> removed
├── status/       # dispatch.log, {id}.status, {id}.session, *.jsonl, watcher logs
├── artifacts/    # {id}.result.md / .result.json / .error.*
├── context/      # symlinks to per-project governance files (optional)
├── blueprints/   # implementation plans (blueprint-writer output)
├── config.yaml   # PROJECT REGISTRY (Step 3)
├── lib-common.sh # shared helpers
├── watcher.sh    # queue watcher (routes by extension)
├── dispatch-claude.sh / dispatch-codex.sh / dispatch-kiro.sh
```

---

## Step 2 — Install the scripts

Copy these from the power's `assets/forge-bridge/` to `~/.forge-bridge/` and make
them executable:

```bash
# (write each file from assets/forge-bridge/*, then:)
chmod +x ~/.forge-bridge/lib-common.sh \
         ~/.forge-bridge/watcher.sh \
         ~/.forge-bridge/dispatch-claude.sh \
         ~/.forge-bridge/dispatch-codex.sh \
         ~/.forge-bridge/dispatch-kiro.sh
```

Files:

- `lib-common.sh` — sourced by everything; resolves binaries via `command -v`,
  provides `acquire_lock`, `notify`, `resolve_project_dir`, `parse_frontmatter`,
  `write_status`, and the shared directory variables.
- `watcher.sh` — watches `queue/` and routes new files to the right dispatcher
  (`*.codex.task.md` and `*.kiro.task.md` checked **before** the generic
  `*.task.md`).
- `dispatch-claude.sh` / `dispatch-codex.sh` / `dispatch-kiro.sh` — one per
  executor, each `flock`-guarded with its own lock file so different executors
  can run concurrently while each executor stays serialized.

Only install the dispatchers for executors the operator actually has. The
watcher tolerates a missing dispatcher's CLI (it logs "not found" and exits 0).

---

## Step 3 — Create the project registry

The registry maps short keys to absolute repo paths on **this** machine. A task
file's optional `project-dir:` frontmatter selects a key; the dispatcher resolves
it to a working directory and strips the frontmatter before the executor sees the
prompt.

```bash
cp <power>/assets/forge-bridge/config.example.yaml ~/.forge-bridge/config.yaml
# then edit paths:
```

```yaml
version: "1.0"
default_project: my-app          # used when a task omits project-dir
projects:
  my-app:  ~/code/my-app
  infra:   ~/code/my-app-infra
  content: ~/code/my-app-content
```

Validate resolution:

```bash
source ~/.forge-bridge/lib-common.sh
resolve_project_dir ""          # -> default project's absolute path
resolve_project_dir "infra"     # -> ~/code/my-app-infra (expanded)
```

If `yq` is installed it is used; otherwise a portable `awk` fallback parses the
YAML. Keep the registry flat (one `key: path` per line under `projects:`).

---

## Step 4 — Install the watcher daemon

### macOS (launchd)

```bash
PLIST=~/Library/LaunchAgents/com.forge.bridge-watcher.plist
# Write assets/daemon/com.forge.bridge-watcher.plist.template with substitutions:
sed -e "s|__HOME__|$HOME|g" \
    -e "s|__PATH__|$HOME/.local/bin:$(brew --prefix)/bin:/usr/local/bin:/usr/bin:/bin|g" \
    <power>/assets/daemon/com.forge.bridge-watcher.plist.template > "$PLIST"

launchctl load "$PLIST"
launchctl list | grep forge      # confirm it's registered
```

The explicit `PATH` is essential — launchd runs with a minimal environment, which
is the root cause of the classic "claude/flock not found" failures.

### Linux (systemd user unit)

```bash
mkdir -p ~/.config/systemd/user
cp <power>/assets/daemon/forge-bridge-watcher.service.template \
   ~/.config/systemd/user/forge-bridge-watcher.service

systemctl --user daemon-reload
systemctl --user enable --now forge-bridge-watcher
systemctl --user status forge-bridge-watcher
# Keep running after logout (optional):
sudo loginctl enable-linger "$USER"
```

### No daemon (foreground / quick test)

```bash
~/.forge-bridge/watcher.sh   # Ctrl-C to stop
```

For **unattended** runs that use Kiro CLI, export `KIRO_API_KEY` in the daemon
environment (both templates have a commented slot) so headless auth works while
you're away.

---

## Step 5 — (Optional) Governance symlinks

If the orchestrator wants quick read access to a project's governance files:

```bash
ln -sf ~/code/my-app/CLAUDE.md            ~/.forge-bridge/context/CLAUDE.md
ln -sf ~/code/my-app/docs/ai/BUNDLE.md    ~/.forge-bridge/context/BUNDLE.md
```

These are convenience pointers only; executors auto-discover governance from the
working directory resolved in Step 3.

---

## Step 6 — Add the in-repo kit to each participating project

Every repo that receives tasks needs the small in-repo kit (subagents, commands,
hooks, the parallel-execution rule, and the reconcile skill). See
`agents-commands-hooks.md` for the full layout. Minimum:

```bash
cd ~/code/my-app
mkdir -p .forge/agents docs/ai/rules/parallel-execution docs/ai/skills/reconcile-parallel-work
# copy assets/governance/parallel-execution.rule.md      -> docs/ai/rules/parallel-execution/RULE.md
# copy assets/governance/reconcile-parallel-work.skill.md -> docs/ai/skills/reconcile-parallel-work/SKILL.md
# copy assets/forge-bridge/manifest.example.yaml          -> .forge/manifest.yaml (then empty active_tasks)
```

---

## Step 7 — Verify end-to-end

```bash
# Watcher alive?
launchctl list | grep forge            # macOS
systemctl --user is-active forge-bridge-watcher   # Linux

# Executor auth (only for those installed):
claude auth status                     # Claude Code
echo "${KIRO_API_KEY:+set}"            # Kiro headless key present?

# Smoke test:
cat > ~/.forge-bridge/queue/smoke-test.task.md <<'EOF'
Respond with only the text: FORGE BRIDGE OK
EOF
sleep 15
cat ~/.forge-bridge/status/smoke-test.status         # -> completed
cat ~/.forge-bridge/artifacts/smoke-test.result.md   # -> FORGE BRIDGE OK
```

If it hangs or fails, load `operations-and-troubleshooting.md`.

---

## Repairing an existing install

- **Watcher not registered** → reload the daemon (macOS `launchctl unload && load`;
  Linux `systemctl --user restart forge-bridge-watcher`).
- **Edited a dispatch script or installed a new dependency** → restart the daemon
  so it runs in a fresh environment.
- **Orphaned `*.running` files** → a prior dispatch crashed. Remove the marker and
  check `artifacts/` for partial output before re-queueing.
- **"binary not found" in dispatch.log** → the CLI isn't on the daemon's `PATH`;
  add its directory to the daemon `PATH` (launchd plist / systemd `Environment=`).

---

## Uninstall

```bash
# macOS
launchctl unload ~/Library/LaunchAgents/com.forge.bridge-watcher.plist
rm ~/Library/LaunchAgents/com.forge.bridge-watcher.plist
# Linux
systemctl --user disable --now forge-bridge-watcher
rm ~/.config/systemd/user/forge-bridge-watcher.service && systemctl --user daemon-reload
# Both (optional — destroys queue/artifacts/logs):
rm -rf ~/.forge-bridge
```
