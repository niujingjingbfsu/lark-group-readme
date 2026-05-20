#!/bin/bash
# Daily ReadMe-check: for each configured group, count yesterday's meaningful
# messages; if active, send a card inviting the owner to draft a ReadMe update.
# The card has a callback button that wakes the agent; the agent NEVER
# auto-creates and NEVER auto-publishes — drafts are previewed first.

set -u

# Resolve repo root relative to this script so the install location is portable.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CONFIG="${LARK_SKILLS_CONFIG:-${SCRIPT_DIR}/groups.conf}"
LOG_DIR="${LARK_SKILLS_LOG_DIR:-${REPO_ROOT}/log}"
LOG="${LOG_DIR}/cron-readme-check.log"
LARK_CLI="${LARK_CLI:-$(command -v lark-cli || echo /usr/local/lib/node_modules/@larksuite/cli/bin/lark-cli)}"
MIN_MSGS="${MIN_MSGS:-3}"

mkdir -p "$LOG_DIR"

log() { echo "$(date -Iseconds) $*" >> "$LOG"; }

if [ ! -x "$LARK_CLI" ]; then
  log "ERROR: lark-cli not found at $LARK_CLI"
  exit 1
fi

if [ ! -f "$CONFIG" ]; then
  log "no config file at $CONFIG, exiting"
  exit 0
fi

# yesterday window: last 24 hours (ISO 8601 UTC, expected by lark-cli)
START="$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)"

while IFS= read -r line; do
  case "$line" in ''|\#*) continue ;; esac
  chat_id=$(echo "$line" | awk '{print $1}')
  group_label=$(echo "$line" | sed -E 's/^[^#]*#?\s*//')

  # Count non-system, non-bot messages.
  count=$("$LARK_CLI" im +chat-messages-list \
    --chat-id "$chat_id" \
    --start "$START" \
    --page-size 50 \
    --format ndjson \
    --as bot 2>>"$LOG" \
    | grep -oE '"msg_type":"(text|post|merge_forward|share_calendar_event)"' \
    | wc -l)

  if [ "${count:-0}" -lt "$MIN_MSGS" ]; then
    log "$chat_id ($group_label): $count msgs in last 24h, skip"
    continue
  fi

  card=$(cat <<EOF
{
  "schema": "2.0",
  "header": {"title": {"tag": "plain_text", "content": "📝 ReadMe 每日检查"}, "template": "blue"},
  "body": {"elements": [
    {"tag": "markdown", "content": "过去 24 小时群里有 **${count} 条**对话。要不要让我看一眼，整理一份 ReadMe 更新草稿给你？\n\n_（如果群里还没有 ReadMe，我会礼貌地提示你先建一份——首次创建必须由你发起。）_"},
    {"tag": "hr"},
    {"tag": "column_set", "columns": [
      {"tag": "column", "elements": [{"tag": "button", "text": {"tag": "plain_text", "content": "👀 看看草稿"}, "type": "primary",
        "behaviors": [{"type": "callback", "value": {"__claude_cb": true, "action": "daily_readme_check"}}]}]},
      {"tag": "column", "elements": [{"tag": "button", "text": {"tag": "plain_text", "content": "今天不用"}, "type": "default",
        "behaviors": [{"type": "callback", "value": {"action": "skip"}}]}]}
    ]}
  ]}
}
EOF
)

  "$LARK_CLI" im +messages-send \
    --chat-id "$chat_id" \
    --msg-type interactive \
    --content "$card" \
    --as bot >>"$LOG" 2>&1

  log "$chat_id ($group_label): sent check card ($count msgs)"
done < "$CONFIG"
