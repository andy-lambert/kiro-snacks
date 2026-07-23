#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# lib-common.sh — shared helpers for the Engine Core Local forge-bridge.
#
# Sourced by every dispatch-*.sh script and by watcher.sh. Its job is to make
# the pipeline portable: no hardcoded /opt/homebrew or /Users/<name> paths, and
# graceful behaviour across macOS (launchd) and Linux (systemd).
#
# It resolves tool binaries via `command -v` with sensible fallbacks so the
# scripts work under a restricted daemon $PATH.
# ---------------------------------------------------------------------------
set -euo pipefail

# --- Base directories -------------------------------------------------------
FORGE_HOME="${FORGE_HOME:-$HOME/.forge-bridge}"
QUEUE_DIR="$FORGE_HOME/queue"
STATUS_DIR="$FORGE_HOME/status"
ARTIFACTS_DIR="$FORGE_HOME/artifacts"
CONTEXT_DIR="$FORGE_HOME/context"
BLUEPRINTS_DIR="$FORGE_HOME/blueprints"
CONFIG_FILE="$FORGE_HOME/config.yaml"
DISPATCH_LOG="$STATUS_DIR/dispatch.log"

mkdir -p "$QUEUE_DIR" "$STATUS_DIR" "$ARTIFACTS_DIR" "$CONTEXT_DIR" "$BLUEPRINTS_DIR"

# --- Binary resolution ------------------------------------------------------
# Ensure common install locations are on PATH even under a minimal daemon env.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

_resolve() { command -v "$1" 2>/dev/null || true; }

FLOCK_BIN="$(_resolve flock)"
JQ_BIN="$(_resolve jq)"
YQ_BIN="$(_resolve yq)"            # optional; a grep fallback is used if absent

# --- Logging ----------------------------------------------------------------
log() { echo "$(date -Iseconds) | $*" >> "$DISPATCH_LOG"; }

# --- Cross-platform desktop notification ------------------------------------
# macOS -> osascript; Linux -> notify-send; otherwise a no-op.
notify() {
  local title="$1" message="$2"
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$message\" with title \"$title\" sound name \"Glass\"" 2>/dev/null || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "$title" "$message" 2>/dev/null || true
  fi
}

# --- Advisory lock ----------------------------------------------------------
# Usage: acquire_lock <lockfile-path> <fd>. Exits 0 (skips) if lock is held.
# Falls back to an atomic mkdir lock when `flock` is unavailable (portable).
acquire_lock() {
  local lockfile="$1" fd="${2:-9}"
  if [ -n "$FLOCK_BIN" ]; then
    eval "exec $fd>\"$lockfile\""
    "$FLOCK_BIN" -n "$fd" || { log "Dispatch already running ($lockfile), skipping"; exit 0; }
  else
    local dirlock="${lockfile}.d"
    if ! mkdir "$dirlock" 2>/dev/null; then
      log "Dispatch already running ($dirlock), skipping"; exit 0
    fi
    trap 'rmdir "'"$dirlock"'" 2>/dev/null || true' EXIT
  fi
}

# --- Project registry resolution -------------------------------------------
# Reads config.yaml and maps a project key -> absolute path. The registry maps
# keys under a top-level `projects:` block, e.g.:
#   projects:
#     my-app: /Users/me/code/my-app
#     infra:  /Users/me/code/infra
#   default_project: my-app
resolve_project_dir() {
  local key="$1" path=""
  if [ -z "$key" ]; then
    key="$(_config_scalar default_project)"
  fi
  [ -z "$key" ] && return 1
  if [ -n "$YQ_BIN" ]; then
    path="$("$YQ_BIN" -r ".projects.\"$key\" // \"\"" "$CONFIG_FILE" 2>/dev/null)"
  else
    # Minimal grep-based fallback: match `  <key>: <path>` under projects:.
    path="$(awk -v k="$key" '
      /^projects:/ {inp=1; next}
      inp && /^[^[:space:]]/ {inp=0}
      inp && $0 ~ "^[[:space:]]+"k"[[:space:]]*:" {
        sub(/^[[:space:]]+[^:]+:[[:space:]]*/,""); gsub(/"/,""); print; exit}
    ' "$CONFIG_FILE" 2>/dev/null)"
  fi
  # Expand a leading ~ to $HOME.
  path="${path/#\~/$HOME}"
  [ -n "$path" ] && printf '%s\n' "$path"
}

_config_scalar() {
  local key="$1"
  if [ -n "$YQ_BIN" ]; then
    "$YQ_BIN" -r ".$key // \"\"" "$CONFIG_FILE" 2>/dev/null
  else
    awk -v k="$key" '$0 ~ "^"k"[[:space:]]*:" {sub(/^[^:]+:[[:space:]]*/,""); gsub(/"/,""); print; exit}' "$CONFIG_FILE" 2>/dev/null
  fi
}

# --- Frontmatter extraction -------------------------------------------------
# Splits a task file into (a) the value of a frontmatter key and (b) the body
# with the frontmatter block removed. Frontmatter is an optional leading
# ---\n...\n--- block. Sets globals FM_VALUE and FM_BODY.
parse_frontmatter() {
  local file="$1" key="$2"
  FM_VALUE=""; FM_BODY=""
  if [ "$(head -1 "$file")" = "---" ]; then
    FM_VALUE="$(awk -v k="$key" '
      NR==1 && $0=="---" {inf=1; next}
      inf && $0=="---" {inf=0; next}
      inf && $0 ~ "^"k"[[:space:]]*:" {sub(/^[^:]+:[[:space:]]*/,""); gsub(/"/,""); print; exit}
    ' "$file")"
    FM_BODY="$(awk 'NR==1 && $0=="---"{inf=1; next} inf && $0=="---"{inf=0; next} !inf{print}' "$file")"
  else
    FM_BODY="$(cat "$file")"
  fi
}

# --- Status writer ----------------------------------------------------------
write_status() {
  local task_id="$1" exit_code="$2"
  if [ "$exit_code" -eq 0 ]; then
    echo "completed" > "$STATUS_DIR/${task_id}.status"
  else
    echo "failed (exit $exit_code)" > "$STATUS_DIR/${task_id}.status"
  fi
}
