#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# watcher.sh — file-system watcher that routes new task files to the correct
# executor dispatcher by extension. Runs under launchd (macOS) or systemd
# (Linux) as a persistent daemon.
#
# Routing is most-specific-first: *.codex.task.md and *.kiro.task.md are
# checked before the generic *.task.md so they don't fall through to Claude.
#
# Prefers fswatch; falls back to inotifywait (Linux) if fswatch is absent.
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-common.sh
source "$SCRIPT_DIR/lib-common.sh"

echo "Forge Bridge Watcher started at $(date -Iseconds)"

route() {
  local event="$1"
  case "$event" in
    *.codex.task.md) log "[codex] Detected: $(basename "$event")"; "$SCRIPT_DIR/dispatch-codex.sh" ;;
    *.kiro.task.md)  log "[kiro] Detected: $(basename "$event")";  "$SCRIPT_DIR/dispatch-kiro.sh" ;;
    *.task.md)       log "Detected: $(basename "$event")";         "$SCRIPT_DIR/dispatch-claude.sh" ;;
  esac
}

if command -v fswatch >/dev/null 2>&1; then
  fswatch -0 --event Created "$QUEUE_DIR" | while read -r -d "" event; do route "$event"; done
elif command -v inotifywait >/dev/null 2>&1; then
  inotifywait -m -e create --format '%w%f' "$QUEUE_DIR" | while read -r event; do route "$event"; done
else
  echo "ERROR: neither fswatch nor inotifywait is installed; cannot watch queue." >&2
  exit 1
fi
