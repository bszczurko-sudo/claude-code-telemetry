#!/usr/bin/env bash
# deploy.sh — bring up the telemetry stack with secrets injected from
# Bitwarden Secrets Manager (bws). Run this ON the VM, from the repo dir.
#
# Prereqs (one-time, see DEPLOY.md):
#   - bws + jq installed
#   - a Bitwarden Secrets Manager machine-account access token
#   - a secret in that project holding the Grafana admin password
#
# Config is read from the environment, or from a gitignored .bws.env next to
# this script if present:
#   BWS_ACCESS_TOKEN   machine-account access token   (required)
#   GF_ADMIN_SECRET_ID uuid of the Grafana-admin secret in bws (required)
set -euo pipefail

cd "$(dirname "$0")"

# Load operator config from a gitignored file if it exists (keeps the token
# out of shell history / the repo). See .bws.env.example.
if [[ -f .bws.env ]]; then
    # shellcheck disable=SC1091
    set -a; . ./.bws.env; set +a
fi

: "${BWS_ACCESS_TOKEN:?set BWS_ACCESS_TOKEN (bws machine-account token) in env or .bws.env}"
: "${GF_ADMIN_SECRET_ID:?set GF_ADMIN_SECRET_ID (uuid of the Grafana admin secret) in env or .bws.env}"

for bin in bws jq docker; do
    command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: '$bin' not found — see DEPLOY.md" >&2; exit 1; }
done

echo "Fetching Grafana admin password from Bitwarden Secrets Manager..."
GF_SECURITY_ADMIN_PASSWORD="$(BWS_ACCESS_TOKEN="$BWS_ACCESS_TOKEN" bws secret get "$GF_ADMIN_SECRET_ID" | jq -r '.value')"
export GF_SECURITY_ADMIN_PASSWORD

if [[ -z "$GF_SECURITY_ADMIN_PASSWORD" || "$GF_SECURITY_ADMIN_PASSWORD" == "null" ]]; then
    echo "ERROR: bws returned an empty value for secret $GF_ADMIN_SECRET_ID" >&2
    exit 1
fi

echo "Secret loaded (${#GF_SECURITY_ADMIN_PASSWORD} chars). Starting stack..."
docker compose up -d

echo "Done. Grafana is starting with the admin password from bws."
echo "Note: Grafana applies GF_SECURITY_ADMIN_PASSWORD on every start, so the"
echo "admin password is reset to the bws value each deploy."
