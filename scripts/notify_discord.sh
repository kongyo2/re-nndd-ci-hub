#!/usr/bin/env bash
# Send a Discord webhook with an embed summary and the full report
# attached as a Markdown file (multipart/form-data).
set -euo pipefail

: "${DISCORD_WEBHOOK_URL:?DISCORD_WEBHOOK_URL is required}"

REPORT_FILE="${REPORT_FILE:-reports/report.md}"
if [[ ! -f "$REPORT_FILE" ]]; then
  echo "report file not found: $REPORT_FILE" >&2
  exit 1
fi

short="${COMMIT_SHORT:-?}"
msg="${COMMIT_MSG:-}"
author="${COMMIT_AUTHOR:-unknown}"
url="${COMMIT_URL:-https://github.com/}"
run_url="${RUN_URL:-}"
sim_count="${SIM_COUNT:-0}"

# Truncate the embed description (Discord limit: 4096 chars; we keep room).
desc=$(printf '**%s**\nby %s\n\n[View commit](%s)' "$msg" "$author" "$url")
if [[ -n "$run_url" ]]; then
  desc+=$'\n'"[CI run]($run_url)"
fi

payload=$(jq -nc \
  --arg title  "Re-NNDD: new commit ${short}" \
  --arg desc   "$desc" \
  --arg url    "$url" \
  --arg footer "similarity-ts hits: ${sim_count}" \
  '{
    username: "Re-NNDD Watcher",
    embeds: [{
      title: $title,
      description: $desc,
      url: $url,
      color: 5814783,
      footer: { text: $footer },
      timestamp: (now | todateiso8601)
    }]
  }')

# Discord caps regular file uploads at 25 MiB; our markdown report
# will always be far smaller than that.
http_status=$(curl -sS -o /tmp/discord.out -w '%{http_code}' \
  -X POST "$DISCORD_WEBHOOK_URL" \
  -F "payload_json=$payload" \
  -F "files[0]=@${REPORT_FILE};type=text/markdown;filename=report.md")

echo "Discord HTTP $http_status"
if [[ "$http_status" -ge 300 ]]; then
  cat /tmp/discord.out
  exit 1
fi
