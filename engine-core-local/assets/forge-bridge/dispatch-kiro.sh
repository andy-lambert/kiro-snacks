#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# dispatch-kiro.sh — Kiro CLI executor for the forge-bridge.
# Triggered by watcher.sh for files matching *.kiro.task.md.
#
# Kiro CLI headless mode: `kiro chat --no-interactive --trust-all-tools "..."`.
# Authenticate non-interactively with an API key exported as KIRO_API_KEY
# (see https://kiro.dev/docs/cli/headless/). Kiro emits plain text (with ANSI
# colour) and has no --output-format json or budget flag, so we strip ANSI and
# capture stdout to the result markdown.
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-common.sh
source "$SCRIPT_DIR/lib-common.sh"

acquire_lock "$FORGE_HOME/.dispatch-kiro.lock" 9

# The binary is `kiro` in Kiro CLI 2.0+; older builds shipped `kiro-cli`.
KIRO_BIN="$(_resolve kiro)"; [ -z "$KIRO_BIN" ] && KIRO_BIN="$(_resolve kiro-cli)"
[ -z "$KIRO_BIN" ] && { log "[kiro] kiro CLI not found on PATH"; exit 0; }

TASK_FILE="$(ls -tr "$QUEUE_DIR"/*.kiro.task.md 2>/dev/null | head -1 || true)"
[ -z "$TASK_FILE" ] && exit 0

TASK_ID="$(basename "$TASK_FILE" .kiro.task.md)"

parse_frontmatter "$TASK_FILE" "project-dir"
WORK_DIR="$(resolve_project_dir "$FM_VALUE" || true)"
if [ -z "$WORK_DIR" ] || [ ! -d "$WORK_DIR" ]; then
  echo "failed (invalid project-dir: '${FM_VALUE:-<default>}')" > "$STATUS_DIR/${TASK_ID}.status"
  log "[kiro] $TASK_ID -> invalid project-dir '${FM_VALUE:-<default>}'"
  exit 0
fi
TASK_PROMPT="$FM_BODY"

log "[kiro] Dispatching: $TASK_ID (dir: $(basename "$WORK_DIR"))"
mv "$TASK_FILE" "$QUEUE_DIR/${TASK_ID}.kiro.running"

cd "$WORK_DIR"
"$KIRO_BIN" chat --no-interactive --trust-all-tools "$TASK_PROMPT" \
  < /dev/null \
  2> "$ARTIFACTS_DIR/${TASK_ID}.stderr.log" \
  | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g' \
  > "$ARTIFACTS_DIR/${TASK_ID}.result.md"
EXIT_CODE=${PIPESTATUS[0]}

write_status "$TASK_ID" "$EXIT_CODE"
[ "$EXIT_CODE" -eq 0 ] || cp "$ARTIFACTS_DIR/${TASK_ID}.stderr.log" "$ARTIFACTS_DIR/${TASK_ID}.error.log" 2>/dev/null || true

rm -f "$QUEUE_DIR/${TASK_ID}.kiro.running"
STATUS="$(cat "$STATUS_DIR/${TASK_ID}.status")"
log "[kiro] $TASK_ID -> $STATUS"
notify "Forge Bridge" "[kiro] $TASK_ID -> $STATUS"
