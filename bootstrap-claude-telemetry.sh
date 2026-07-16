#!/usr/bin/env bash
# bootstrap-claude-telemetry.sh — merge the telemetry `env` block from
# claude-code-telemetry-settings.json into ~/.claude/settings.json so a
# Claude Code client on this machine exports telemetry to the collector.
#
# Idempotent: re-running just re-applies the same env block. Preserves any
# other keys already in settings.json (e.g. "theme"). Optional first arg
# overrides the OTLP endpoint (e.g. http://<VM_PUBLIC_IP>:4317 for a remote client).
set -euo pipefail

cd "$(dirname "$0")"
TEMPLATE="claude-code-telemetry-settings.json"
DEST="$HOME/.claude/settings.json"
ENDPOINT="${1:-}"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not found" >&2; exit 1; }
[[ -f "$TEMPLATE" ]] || { echo "ERROR: $TEMPLATE not found" >&2; exit 1; }

mkdir -p "$HOME/.claude"
[[ -f "$DEST" ]] || echo '{}' > "$DEST"
cp "$DEST" "$DEST.bak"

# Strip the "//..." doc keys from the template's env, optionally override endpoint,
# then deep-merge env into the existing settings.json.
ENVBLOCK="$(jq '.env' "$TEMPLATE")"
if [[ -n "$ENDPOINT" ]]; then
    ENVBLOCK="$(echo "$ENVBLOCK" | jq --arg e "$ENDPOINT" '.OTEL_EXPORTER_OTLP_ENDPOINT = $e')"
fi

jq --argjson env "$ENVBLOCK" '.env = ((.env // {}) + $env)' "$DEST.bak" > "$DEST"

echo "Merged telemetry env into $DEST (backup at $DEST.bak):"
jq '.env' "$DEST"
echo
echo "New Claude Code sessions on this machine will now export telemetry."
