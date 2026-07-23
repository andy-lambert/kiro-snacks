#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# dispatch-claude.sh — Claude Code CLI executor for the forge-bridge.
# Triggered by watcher.sh for files matching *.task.md (NOT *.codex.task.md
# or *.kiro.task.md, which have their own dispatchers).
#
# Lifecycle: {id}.task.md -> {id}.running -> removed. Result JSON + extracted
# markdown land in artifacts/; status in status/.
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-common.sh
source "$SCRIPT_DIR/lib-common.sh"

acquire_lock "$FORGE_HOME/.dispatch-claude.lock" 9

CLAUDE_BIN="$(_resolve claude)"
[ -z "$CLAUDE_BIN" ] && { log "[claude] claude CLI not found on PATH"; exit 0; }

# Pick the oldest *plain* .task.md (exclude the specialized executor patterns).
TASK_FILE="$(ls -tr "$QUEUE_DIR"/*.task.md 2>/dev/null | grep -Ev '\.(codex|kiro)\.task\.md$' | head -1 || true)"
[ -z "$TASK_FILE" ] && exit 0

TASK_ID="$(basename "$TASK_FILE" .task.md)"

# Resolve target repo from optional `project-dir:` frontmatter; strip frontmatter.
parse_frontmatter "$TASK_FILE" "project-dir"
WORK_DIR="$(resolve_project_dir "$FM_VALUE" || true)"
if [ -z "$WORK_DIR" ] || [ ! -d "$WORK_DIR" ]; then
  echo "failed (invalid project-dir: '${FM_VALUE:-<default>}')" > "$STATUS_DIR/${TASK_ID}.status"
  log "[claude] $TASK_ID -> invalid project-dir '${FM_VALUE:-<default>}'"
  exit 0
fi
TASK_PROMPT="$FM_BODY"

log "[claude] Dispatching: $TASK_ID (dir: $(basename "$WORK_DIR"))"
mv "$TASK_FILE" "$QUEUE_DIR/${TASK_ID}.running"

MAX_BUDGET="${FORGE_CLAUDE_MAX_BUDGET_USD:-1.00}"
cd "$WORK_DIR"
"$CLAUDE_BIN" -p "$TASK_PROMPT" \
  --output-format json \
  --allowedTools "Read,Write,Edit,Bash,Grep,Glob,WebFetch,WebSearch,Agent" \
  --max-budget-usd "$MAX_BUDGET" \
  < /dev/null \
  > "$ARTIFACTS_DIR/${TASK_ID}.result.json" 2>&1
EXIT_CODE=$?

write_status "$TASK_ID" "$EXIT_CODE"
if [ "$EXIT_CODE" -eq 0 ] && [ -n "$JQ_BIN" ]; then
  "$JQ_BIN" -r '.result // "No result text"' "$ARTIFACTS_DIR/${TASK_ID}.result.json" \
    > "$ARTIFACTS_DIR/${TASK_ID}.result.md" 2>/dev/null || cp "$ARTIFACTS_DIR/${TASK_ID}.result.json" "$ARTIFACTS_DIR/${TASK_ID}.result.md"
  SESSION_ID="$("$JQ_BIN" -r '.session_id // empty' "$ARTIFACTS_DIR/${TASK_ID}.result.json" 2>/dev/null)"
  [ -n "$SESSION_ID" ] && echo "$SESSION_ID" > "$STATUS_DIR/${TASK_ID}.session"
else
  cp "$ARTIFACTS_DIR/${TASK_ID}.result.json" "$ARTIFACTS_DIR/${TASK_ID}.error.json" 2>/dev/null || true
fi

rm -f "$QUEUE_DIR/${TASK_ID}.running"
STATUS="$(cat "$STATUS_DIR/${TASK_ID}.status")"
log "[claude] $TASK_ID -> $STATUS"
notify "Forge Bridge" "[claude] $TASK_ID -> $STATUS"
