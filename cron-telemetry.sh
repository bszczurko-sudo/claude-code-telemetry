#!/usr/bin/env bash
# cron-telemetry.sh — run a small REAL Claude Code session on the VM so the
# telemetry stack has a steady stream of real data with no external client.
# The telemetry config (OTLP endpoint + ingest token) lives in
# ~/.claude/settings.json, so any session here exports authenticated telemetry.
#
# Install (hourly):
#   (crontab -l 2>/dev/null; echo "0 * * * * /home/ubuntu/claude-code-telemetry/cron-telemetry.sh") | crontab -
set -uo pipefail

export HOME=/home/ubuntu
CLAUDE="$HOME/.local/bin/claude"
PROJECT="$HOME/claude-code-telemetry"
LOG="$PROJECT/cron-telemetry.log"

cd "$PROJECT" || exit 1
TS="$(date -u +%FT%TZ)"

# Keep the prompt tool-free so no permission prompt is needed in headless mode.
OUT="$(timeout 120 "$CLAUDE" -p "Reply with one short sentence confirming the telemetry heartbeat is alive." --output-format text 2>&1)"
RC=$?

# Trim log to last 500 lines to keep it bounded.
{
  echo "[$TS] rc=$RC :: ${OUT:0:200}"
} >> "$LOG"
tail -n 500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"

exit 0
