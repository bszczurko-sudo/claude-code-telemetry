# Claude Code Telemetry Stack — OPS-235

## Project Overview
Self-hosted telemetry collection stack for tracking Claude Code usage across EdgeBeam Wireless. Collects token usage, session counts, estimated cost, and code suggestion acceptance/rejection rates. Data displayed on an auto-provisioned Grafana dashboard.

## Architecture
```
Claude Code clients → OTel Collector (4317 gRPC / 4318 HTTP)
                          ├── push logs → Loki (:3100)
                          └── expose metrics on :8889 → scraped by Prometheus (:9090)
                      Grafana (:3000) queries both Prometheus and Loki
```
Grafana has both datasources provisioned: Prometheus (uid `PBFA97CFB590B2093`, matching the dashboard panel references) and Loki (uid `loki`).

## Stack
- **Orchestration:** Docker Compose
- **Telemetry intake:** OpenTelemetry Collector (otel/opentelemetry-collector-contrib)
- **Metrics storage:** Prometheus (scrapes collector on port 8889 every 30s)
- **Log storage:** Loki (receives pushes via otlp_http from collector)
- **Dashboard:** Grafana (auto-provisioned datasource + dashboard via JSON)
- **Test data:** Python script using opentelemetry-sdk pushing via OTLP gRPC

## File Structure
```
claude-code-telemetry/
├── docker-compose.yml                          # Four-service stack with volumes, restart, depends_on
├── otel-collector-config.yaml                  # OTLP receivers, batch processor, Prometheus + Loki exporters
├── prometheus.yml                              # 30s scrape config targeting collector:8889
├── test_telemetry.py                           # Continuous synthetic data generator (5 users, 5 metrics)
├── provisioning/
│   ├── datasources/datasources.yml             # Auto-configures Prometheus + Loki in Grafana
│   └── dashboards/
│       ├── dashboards.yml                      # Points Grafana to JSON dashboard files
│       └── claude-code-analytics.json          # Auto-provisioned dashboard (5 panels)
├── CLAUDE.md                                   # This file
└── .gitignore                                  # Excludes .env
```

## Metrics
| Metric | Type | Description |
|--------|------|-------------|
| claude_code_tokens_used_total | Counter | Tokens consumed per user/model |
| claude_code_sessions_total | Counter | Sessions initiated per user/model |
| claude_code_estimated_cost_total | Counter | Cost at $3/million tokens |
| claude_code_suggestions_accepted_total | Counter | Code suggestions accepted |
| claude_code_suggestions_rejected_total | Counter | Code suggestions rejected |

All metrics carry labels: `user`, `model`

## Dashboard Panels
1. **Token Use** (stat) — `claude_code_tokens_used_total` by user
2. **Total Claude Sessions** (stat) — `claude_code_sessions_total` by user
3. **Claude Cost** (gauge) — `claude_code_estimated_cost_total` by user
4. **Suggestions Accepted** (stat) — `claude_code_suggestions_accepted_total` by user
5. **Acceptance Rate** (gauge, %) — accepted / (accepted + rejected) by user

> Stat panels reduce with `lastNotNull` on cumulative counters, so they show running totals. Switch to `rate()`/`increase()` if per-interval usage is wanted.

## Deployment
- **VM:** EC2 t3.small, Ubuntu 24.04, us-east-1
- **Public IP:** 18.215.170.79
- **Grafana:** http://18.215.170.79:3000
- **Repo:** https://github.com/bszczurko-sudo/claude-code-telemetry

## Key Decisions
- Push model (OTLP) for Claude Code → Collector, pull model (scrape) for Collector → Prometheus
- `otlp_http/loki` exporter (not deprecated `loki` or `otlphttp`)
- Grafana provisioning via mounted files, not manual UI config
- Named Docker volumes for persistence across restarts
- `restart: unless-stopped` on all services

## Coding Standards
- Python 3.14 on macOS, Python 3.x on Ubuntu VM
- OpenTelemetry SDK for all metric/log pushing
- Counters only (no Gauges yet) — add() is the only method
- YAML configs: always validate spelling (receivers not recievers), no duplicate keys
- Dashboard changes: edit in Grafana UI, export JSON, replace provisioning file

## Jira
- Ticket: OPS-235 (parent: OPS-8)
- Assignee: Brett Szczurko
- Stakeholders: Joseph Lancaster (analytics), Don Dewar (ticket creator), Huseyin Esin (AWS/VM)

## What's Left
- Connect real Claude Code clients (env vars on dev machines)
- Publish Confluence runbook (currently draft)
- Transfer repo to edgebeamwireless GitHub org
- Replace placeholder Grafana password

