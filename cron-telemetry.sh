#!/usr/bin/env bash
# cron-telemetry.sh — run a small REAL Claude Code session on the VM so the
# telemetry stack has a steady stream of real data with no external client.
# The telemetry config (OTLP endpoint + ingest token) lives in
# ~/.claude/settings.json, so any session here exports authenticated telemetry.
#
# Each run also performs a real, CHANGING file edit under acceptEdits so it emits
# a claude_code.code_edit_tool.decision{decision="accept"} — keeping the Code
# Acceptance panel populated (in addition to session/token/cost/active_time).
# The timestamp guarantees the content differs each run, so Claude always edits
# (if the content were unchanged it would skip the edit and emit no decision).
#
# Install (hourly):
#   (crontab -l 2>/dev/null; echo "0 * * * * /home/ubuntu/claude-code-telemetry/cron-telemetry.sh") | crontab -
set -uo pipefail

export HOME=/home/ubuntu
CLAUDE="$HOME/.local/bin/claude"
PROJECT="$HOME/claude-code-telemetry"
LOG="$PROJECT/cron-telemetry.log"

cd "$PROJECT" || exit 1
mkdir -p .heartbeat
TS="$(date -u +%FT%TZ)"

# </dev/null so `claude -p` never tries to read the cron stdin as prompt input.
OUT="$(timeout 120 "$CLAUDE" -p "Overwrite the file .heartbeat/beat.txt so its only contents are exactly this line: heartbeat $TS" \
  --permission-mode acceptEdits --output-format text </dev/null 2>&1)"
RC=$?

{ echo "[$TS] rc=$RC :: ${OUT:0:160}"; } >> "$LOG"
tail -n 500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
exit 0
