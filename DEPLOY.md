# Deploying the OPS-235 Telemetry Stack

The stack runs via `docker compose` on the VM (`ubuntu@<VM_PUBLIC_IP>`,
`~/claude-code-telemetry`). Secrets live in a **gitignored `.env`** on the VM,
never in the repo.

## Components
- `docker-compose.yml` — otel-collector, prometheus, loki, grafana
- `otel-collector-config.yaml` — OTLP (bearer-auth) in → Prometheus + Loki
- `provisioning/` — Grafana datasources + the analytics dashboard
- `bootstrap-claude-telemetry.sh` — point a Claude Code client at the collector
- `update-sg.sh` + `team-ips.txt` — manage who can reach the collector

## Secrets (`.env` on the VM)
```bash
cd ~/claude-code-telemetry
cp .env.example .env && chmod 600 .env
# then set:
#   GRAFANA_ADMIN_PASSWORD=<strong value>
#   OTEL_INGEST_TOKEN=$(openssl rand -hex 32)   # shared telemetry-push token
```
`docker-compose.yml` requires both `${GRAFANA_ADMIN_PASSWORD:?}` and
`${OTEL_INGEST_TOKEN:?}` — the stack refuses to start if either is unset, so it
never boots with a blank Grafana password or auth disabled.

## Deploy
```bash
cd ~/claude-code-telemetry
git pull
docker compose up -d
```
Note: Grafana only reads `GF_SECURITY_ADMIN_PASSWORD` on **first** volume init.
To rotate the admin password later, edit `.env` **and** run:
`docker compose exec grafana grafana cli admin reset-admin-password <new>`.

## TLS / public HTTPS (Caddy — OPS-405)
`caddy` terminates TLS for **https://telemetry.edgebeam.dev** (Let's Encrypt,
auto-renewed) and reverse-proxies `/v1/*` → `otel-collector:4318` and everything
else → `grafana:3000`. Grafana (3000) and OTLP-HTTP (4318) are bound to
**loopback**; external access is via Caddy only. Direct gRPC (4317) stays public.

Requirements / gotchas:
- **DNS**: `telemetry.edgebeam.dev` must resolve to the VM's public IP.
- **Security group**: ports **80 and 443 must be open to `0.0.0.0/0`** for ACME
  validation + public HTTPS. These are managed **outside `update-sg.sh`** (which
  rejects `0.0.0.0/0` and only reconciles 22/3000/4317/4318) — add once with:
  ```bash
  aws ec2 authorize-security-group-ingress --group-id sg-0c10615c3983e2f47 --region us-east-1 \
    --ip-permissions 'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0}]' \
                     'IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=0.0.0.0/0}]'
  ```
- **Caddy runs as uid 1000** with `read_only` rootfs; its `caddy_data`/`caddy_certs`
  named volumes must be owned by 1000 or cert storage fails. On first bring-up:
  ```bash
  docker volume create claude-code-telemetry_caddy_data
  docker volume create claude-code-telemetry_caddy_certs
  docker run --rm -v claude-code-telemetry_caddy_data:/data \
    -v claude-code-telemetry_caddy_certs:/config alpine \
    chown -R 1000:1000 /data /config
  ```
- The SG still allows 3000 to the operator IP but nothing listens there publicly
  now (Grafana is loopback) — harmless; can be removed from the allowlist.

---

## Authentication model
The OTLP receivers (4317/4318) require a **shared bearer token**
(`OTEL_INGEST_TOKEN`). A push without `Authorization: Bearer <token>` is rejected
with 401. Network access is additionally gated by the security group (below), so
a client needs **both** an allowlisted IP **and** the token.

User identity on the dashboard comes from each person's own Claude login
(`user_email` label) — not from the token — so one shared token still yields
per-person breakdowns.

## Onboarding a new user (telemetry-push)
1. **Allowlist their IP.** Add a line to `team-ips.txt`:
   ```
   203.0.113.9   Jane (home)
   ```
   Commit it, then run `./update-sg.sh` (opens 4317/4318 for that IP only — no
   SSH/Grafana). Requires a **static** IP; cellular/dynamic IPs won't stay valid.
2. **Give them the token** (`OTEL_INGEST_TOKEN`) over a secure channel.
3. **They configure their client** from a clone of this repo:
   ```bash
   ./bootstrap-claude-telemetry.sh <OTEL_INGEST_TOKEN> http://<VM_PUBLIC_IP>:4317
   ```
   New Claude Code sessions on their machine then export authenticated telemetry.

**Removing a user:** delete their line from `team-ips.txt`, run `./update-sg.sh`.
To fully cut off everyone at once, rotate `OTEL_INGEST_TOKEN` in `.env` and
`docker compose up -d`.

## Enabling telemetry on the VM itself
```bash
./bootstrap-claude-telemetry.sh "$(grep ^OTEL_INGEST_TOKEN= .env | cut -d= -f2)"
```
(defaults to `http://localhost:4317`). Verify data is arriving:
```bash
curl -s http://localhost:9090/api/v1/label/__name__/values | jq -r '.data[]' | grep claude
```
Metrics take up to ~40s to appear (10s client export + 30s Prometheus scrape).
Set the Grafana time range wide enough (e.g. 24h) — per-session series go stale
(see STATUS.md).

## Self-contained data generation (VM cron)
So the dashboard shows a steady stream of REAL data without depending on any
external client (e.g. a laptop), an hourly cron on the VM runs a tiny real
Claude Code session. Telemetry config in `~/.claude/settings.json` makes that
session export authenticated metrics to the local collector.

- Script: `cron-telemetry.sh` (logs to `cron-telemetry.log`, kept to 500 lines)
- Install (hourly):
  ```bash
  (crontab -l 2>/dev/null; echo "0 * * * * /home/ubuntu/claude-code-telemetry/cron-telemetry.sh") | crontab -
  ```
- Change frequency by editing the cron schedule (`crontab -e`). Each run uses a
  small amount of API credit on the VM's logged-in Claude account.

This is what lets the VM "stand on its own": stack + telemetry source + data
generation all live on the VM; your Mac is only for operator access.

## Surviving reboots / crashes
The stack comes back automatically after a reboot or crash:
- `docker` + `containerd` + `cron` are enabled on boot.
- Every container is `restart: unless-stopped`, so running containers revive when
  the Docker daemon restarts (with the token baked in from `.env`).
- `telemetry-stack.service` (systemd) additionally runs `docker compose up -d` on
  boot — this also recovers the stack if the containers were removed, and
  re-applies `.env`. Install once:
  ```bash
  sudo cp telemetry-stack.service /etc/systemd/system/
  sudo systemctl daemon-reload && sudo systemctl enable telemetry-stack.service
  ```
- Named volumes (`prometheus_data`, `loki_data`, `grafana_data`) persist all data.
- The hourly `cron-telemetry.sh` job resumes on its own (cron is enabled on boot).

So a `sudo reboot` (or an unexpected crash) needs no manual intervention.

## Security-group access
`update-sg.sh` reconciles `sg-0c10615c3983e2f47` to exactly: the operator's
current IP (all ports) + every `team-ips.txt` entry (4317/4318 only). Re-run it
whenever the operator's cellular IP rotates — it won't evict teammates.
```bash
./update-sg.sh            # apply
./update-sg.sh --dry-run  # preview changes
./update-sg.sh --status   # show current rules
```
The script verifies it's running against AWS account `027654771904` before any
change, validates every CIDR (rejects anything wider than /24 and `0.0.0.0/0`),
and authorizes new rules before revoking stale ones (no lockout).

### IAM: least-privilege for the SG script
`update-sg.sh` needs only three EC2 actions, scoped to the one security group.
The minimum policy is committed as **`iam-policy.json`**. Operators should run
the script under a **dedicated IAM user or SSO role that has only this policy**
attached — not broad/admin credentials. Apply it, e.g.:
```bash
aws iam put-user-policy --user-name <sg-operator> \
  --policy-name telemetry-sg-manage --policy-document file://iam-policy.json
```
