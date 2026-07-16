# Deploying the OPS-235 Telemetry Stack

The stack runs via `docker compose` on the VM (`ubuntu@<VM_PUBLIC_IP>`,
`~/claude-code-telemetry`). The Grafana admin password is **not** stored in the
repo — it's injected at deploy time from **Bitwarden Secrets Manager** (`bws`).

## Components
- `docker-compose.yml` — otel-collector, prometheus, loki, grafana
- `otel-collector-config.yaml` — OTLP in → Prometheus (metrics) + Loki (logs)
- `provisioning/` — Grafana datasources + the analytics dashboard
- `deploy.sh` — pulls secrets from `bws`, then `docker compose up -d`
- `bootstrap-claude-telemetry.sh` — configures a Claude Code client to emit telemetry

---

## 1. One-time: Bitwarden Secrets Manager setup

Done once by someone with access to the Bitwarden org's Secrets Manager.

1. **Create a project** (e.g. `ops-claude-code-telemetry`).
2. **Add a secret** in that project holding the Grafana admin password:
   - key: `GF_SECURITY_ADMIN_PASSWORD` (any strong value)
   - note its **UUID** — this is `GF_ADMIN_SECRET_ID`.
3. **Create a machine account**, give it **read** access to the project, and
   generate an **access token** — this is `BWS_ACCESS_TOKEN`.

## 2. One-time on the VM: install tooling

```bash
# jq is usually present; bws is not. Install the bws binary (Linux x86_64):
BWS_VER=1.0.0   # pin to the current release
curl -fsSL -o /tmp/bws.zip \
  "https://github.com/bitwarden/sdk-sm/releases/download/bws-v${BWS_VER}/bws-x86_64-unknown-linux-gnu-${BWS_VER}.zip"
unzip -o /tmp/bws.zip -d ~/.local/bin && chmod +x ~/.local/bin/bws
bws --version
```

## 3. One-time on the VM: operator config

```bash
cd ~/claude-code-telemetry
cp .bws.env.example .bws.env
chmod 600 .bws.env
# edit .bws.env, fill in BWS_ACCESS_TOKEN and GF_ADMIN_SECRET_ID
```
`.bws.env` is gitignored — it holds the access token and must never be committed.

## 4. Deploy

```bash
cd ~/claude-code-telemetry
git pull
./deploy.sh
```
`deploy.sh` reads `.bws.env`, fetches the Grafana password from `bws`, exports it
as `GF_SECURITY_ADMIN_PASSWORD`, and runs `docker compose up -d`. The compose
file uses `${GF_SECURITY_ADMIN_PASSWORD:?}`, so a plain `docker compose up`
without the secret **fails fast** instead of booting with a blank password.

> Grafana applies `GF_SECURITY_ADMIN_PASSWORD` on every start, so each deploy
> resets the admin password to the current bws value. Rotate the secret in
> Bitwarden, then re-run `./deploy.sh`.

---

## Making Claude Code emit real telemetry

Telemetry is enabled per-client via an `env` block in `~/.claude/settings.json`
(template: `claude-code-telemetry-settings.json`). To apply it:

```bash
# On the VM (client + collector on the same host):
./bootstrap-claude-telemetry.sh

# From a remote machine (e.g. a laptop) — point at the VM and ensure the SG
# allows your IP on 4317/4318 (use ./update-sg.sh):
./bootstrap-claude-telemetry.sh http://<VM_PUBLIC_IP>:4317
```

Verify data is arriving:
```bash
curl -s http://localhost:9090/api/v1/label/__name__/values | jq -r '.data[]' | grep claude
```
Metrics take up to ~40s to appear (10s client export interval + 30s Prometheus
scrape). Set the Grafana dashboard's time range wide enough (e.g. 24h) to cover
past activity — see STATUS.md for why (per-session series go stale).

## Security-group access

Ports 22/3000/4317/4318 on `sg-0c10615c3983e2f47` are locked to a single
operator IP, which rotates on cellular. Refresh before connecting:
```bash
./update-sg.sh
```
