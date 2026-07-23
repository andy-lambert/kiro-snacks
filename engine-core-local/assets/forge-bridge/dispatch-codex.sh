#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# dispatch-codex.sh — Codex CLI (GPT-family) executor for the forge-bridge.
# Triggered by watcher.sh for files matching *.codex.task.md.
#
# Codex has no per-task budget flag and emits plain text, so we strip ANSI and
# capture stdout straight to the result markdown. Keep prompts tightly scoped
# and include explicit "Do NOT modify" lists (Codex models can expand scope).
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-common.sh
source "$SCRIPT_DIR/lib-common.sh"

acquire_lock "$FORGE_HOME/.dispatch-codex.lock" 9

CODEX_BIN="$(_resolve codex)"
[ -z "$CODEX_BIN" ] && { log "[codex] codex CLI not found on PATH"; exit 0; }

TASK_FILE="$(ls -tr "$QUEUE_DIR"/*.codex.task.md 2>/dev/null | head -1 || true)"
[ -z "$TASK_FILE" ] && exit 0

TASK_ID="$(basename "$TASK_FILE" .codex.task.md)"

parse_frontmatter "$TASK_FILE" "project-dir"
WORK_DIR="$(resolve_project_dir "$FM_VALUE" || true)"
if [ -z "$WORK_DIR" ] || [ ! -d "$WORK_DIR" ]; then
  echo "failed (invalid project-dir: '${FM_VALUE:-<default>}')" > "$STATUS_DIR/${TASK_ID}.status"
  log "[codex] $TASK_ID -> invalid project-dir '${FM_VALUE:-<default>}'"
  exit 0
fi
TASK_PROMPT="$FM_BODY"

log "[codex] Dispatching: $TASK_ID (dir: $(basename "$WORK_DIR"))"
mv "$TASK_FILE" "$QUEUE_DIR/${TASK_ID}.codex.running"

cd "$WORK_DIR"
# `codex exec` runs a single non-interactive turn. --full-auto grants tool use.
"$CODEX_BIN" exec --full-auto "$TASK_PROMPT" \
  < /dev/null \
  2> "$ARTIFACTS_DIR/${TASK_ID}.stderr.log" \
  | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g' \
  > "$ARTIFACTS_DIR/${TASK_ID}.result.md"
EXIT_CODE=${PIPESTATUS[0]}

write_status "$TASK_ID" "$EXIT_CODE"
[ "$EXIT_CODE" -eq 0 ] || cp "$ARTIFACTS_DIR/${TASK_ID}.stderr.log" "$ARTIFACTS_DIR/${TASK_ID}.error.log" 2>/dev/null || true

rm -f "$QUEUE_DIR/${TASK_ID}.codex.running"
STATUS="$(cat "$STATUS_DIR/${TASK_ID}.status")"
log "[codex] $TASK_ID -> $STATUS"
notify "Forge Bridge" "[codex] $TASK_ID -> $STATUS"
