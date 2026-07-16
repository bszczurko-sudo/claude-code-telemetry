# OPS-235 Telemetry Stack — Status & Handoff

_Last updated: 2026-07-15 — handoff for Joe_

## TL;DR
Real Claude Code telemetry is flowing into the VM (previously it was only
synthetic data from `test_telemetry.py`). The stack is healthy, and the Grafana
dashboard has been **repointed to the real metric names and now renders real
data** (verified end-to-end through the Grafana datasource proxy). Remaining work
is mostly codifying config into the repo — see "Remaining work" below.

## Environment
- **VM**: `ubuntu@18.215.170.79` (EC2 `i-0aec393b021b5ef2c`, `ops-claude-code-telemetry`, us-east-1)
  - SSH key: `~/.ssh/ops-telemetry-key.pem`
  - Security group `sg-0c10615c3983e2f47` (ports 22/3000/4317/4318) is locked to a single
    operator IP. It rotates on cellular; refresh with `./update-sg.sh` before connecting.
- **Stack** (docker compose in `~/claude-code-telemetry` on the VM):
  - otel-collector (OTLP gRPC 4317 / HTTP 4318, Prometheus exporter :8889)
  - prometheus (:9090) · grafana (:3000) · loki (:3100)
  - Grafana UI: http://18.215.170.79:3000

## What works
- All four containers up and healthy.
- OTLP receiver accepting data on 4317/4318.
- Prometheus scraping the collector; Grafana provisioned with the Prometheus + Loki datasources.
- **Real** Claude Code telemetry confirmed arriving (see snapshot below).

## What I changed this session
1. Configured real telemetry on the VM in `~/.claude/settings.json` (`env` block):
   `CLAUDE_CODE_ENABLE_TELEMETRY=1`, `OTEL_METRICS_EXPORTER=otlp`,
   `OTEL_LOGS_EXPORTER=otlp`, `OTEL_EXPORTER_OTLP_PROTOCOL=grpc`,
   `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317`, plus short export intervals.
   (Backup at `~/.claude/settings.json.bak`.) **Not yet captured in this repo.**
2. Ran 3 real headless Claude Code sessions on the VM to emit genuine metrics.
3. Verified real metric families now exist in Prometheus.

## Real-data snapshot (from the 3 sessions)
| Metric | Value |
|---|---|
| `claude_code_session_count_total` | 3 sessions |
| `claude_code_token_usage_tokens_total` | 69,504 (input 1,614 / output 342 / cacheRead 60,504 / cacheCreation 7,044) |
| `claude_code_cost_usage_USD_total` | $0.10978 |
| `claude_code_active_time_seconds_total` | 8.4s |
| user label | `user_email="bszczurko@edgebeamwireless.com"` |

## ✅ Fixed this session (dashboard now renders real data)
All five panels in `provisioning/dashboards/claude-code-analytics.json` were
repointed from the synthetic metric names to the real Claude Code metrics, and
legends changed from `{{user}}` to `{{user_email}}`:

| Panel | New query |
|---|---|
| Token Use | `sum by (user_email) (last_over_time(claude_code_token_usage_tokens_total[$__range]))` |
| Total Claude Sessions | `sum by (user_email) (last_over_time(claude_code_session_count_total[$__range]))` |
| Claude Cost | `sum by (user_email) (last_over_time(claude_code_cost_usage_USD_total[$__range]))` |
| Code Acceptance | `sum by (user_email) (last_over_time(claude_code_code_edit_tool_decision_total{decision="accept"}[$__range]))` |
| Code Rejection | `sum by (user_email) (last_over_time(claude_code_code_edit_tool_decision_total{decision="reject"}[$__range]))` |

**Why `last_over_time(...[$__range])` and not a plain `sum`:** real Claude Code
tags every metric with a unique `session_id`, so each session is its own series.
When a session ends, its series stops updating and goes stale — a plain
`sum by (user_email)` instant query then only counts *currently-running* sessions
(reads ~0 when nobody is active). `last_over_time(...[$__range])` grabs each
session's final value across the panel's selected time range, so the stat/gauge
panels total correctly across ended sessions. **Implication for Joe:** set the
dashboard time range wide enough to cover the activity you want to see (e.g. 24h);
a range shorter than the gap since last activity will read empty.

Verified end-to-end via the Grafana datasource proxy — Token Use / Sessions /
Cost / Acceptance all return real values; Rejection is legitimately empty until a
real reject happens.

## Operational notes
- **Scrape latency ~30–40s.** Metrics export every 10s (collector) but Prometheus
  scrapes every 30s, so fresh activity takes up to ~40s to appear. Don't panic if a
  brand-new session isn't on the dashboard for a few seconds.
- **Grafana admin password** in `docker-compose.yml` is the literal placeholder
  `<from-secrets-manager>` — never wired to a real secret. Works today but should be
  fixed.

## ✅ Config codified + secret moved to Bitwarden (this session)
The repo is now the source of truth; the VM was reset to `origin/main` (clean).
- Pulled the VM's uncommitted working state into git: `datasources.yml` (adds Loki +
  pins Prometheus uid `PBFA97CFB590B2093`), `otel-collector-config.yaml` (exporter
  tweaks), `test_telemetry.py` (real metric names), and `CLAUDE.md`.
- Grafana admin password no longer hardcoded. `docker-compose.yml` reads
  `${GF_SECURITY_ADMIN_PASSWORD:?}`; `deploy.sh` injects it from **Bitwarden Secrets
  Manager** (`bws`). Telemetry client config is codified in
  `claude-code-telemetry-settings.json` + `bootstrap-claude-telemetry.sh`.
- Full runbook in **DEPLOY.md**.

### ⚠️ One manual step before the next VM deploy
The stack is still *running* with the old password, but `docker compose` on the VM
now requires the secret. Before the next `./deploy.sh`, someone with Bitwarden
Secrets Manager access must (see DEPLOY.md §1–3): create the `bws` secret + machine
account token, install `bws` on the VM, and create `~/claude-code-telemetry/.bws.env`.
(Until then, inspect containers with `docker ps`, not `docker compose ps`.)

## Remaining work
1. ~~Populate the Rejection panel~~ **Done** — drove a real denied edit (temporary
   `PreToolUse` deny hook on the VM) so `claude_code_code_edit_tool_decision_total{decision="reject"}`
   = 1. All five panels now have real data. The hook was removed afterward.
2. **Retire the synthetic generator** (`test_telemetry.py`) — optional; it now emits
   real metric names and is handy for smoke-testing an empty stack.
3. **Scrape latency / secret rotation** — minor ops items noted above.

## How to reproduce / drive more real data
```bash
./update-sg.sh                                   # refresh SG to your current IP
ssh -i ~/.ssh/ops-telemetry-key.pem ubuntu@18.215.170.79
# on the VM (telemetry already configured in ~/.claude/settings.json):
~/.local/bin/claude -p "summarize this repo" --output-format text
# check Prometheus:
curl -s http://localhost:9090/api/v1/label/__name__/values | jq -r '.data[]' | grep claude
```

## Decommission note
`test_telemetry.py` (synthetic generator) can be retired once the dashboard is
pointed at the real metric names — keep it around only for smoke-testing an empty stack.
