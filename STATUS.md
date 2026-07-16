# OPS-235 Telemetry Stack — Status & Handoff

_Last updated: 2026-07-15 — handoff for Joe_

## TL;DR
Real Claude Code telemetry is now flowing into the VM (previously it was only
synthetic data from `test_telemetry.py`). The stack is healthy. There are **two
schema mismatches** that mean the existing Grafana dashboard does **not** render
the real data yet — those are the main things to work on.

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

## ⚠️ Gaps to work on (this is the actual work)
1. **Metric-name mismatch — dashboard shows nothing for real data.**
   The dashboard queries the *synthetic* names emitted by `test_telemetry.py`;
   real Claude Code emits different names:

   | Dashboard queries (synthetic) | Real Claude Code metric |
   |---|---|
   | `claude_code_tokens_used_total` | `claude_code_token_usage_tokens_total` (label `type`) |
   | `claude_code_sessions_total` | `claude_code_session_count_total` |
   | `claude_code_estimated_cost_total` | `claude_code_cost_usage_USD_total` |
   | `claude_code_suggestions_accepted_total` / `_rejected_total` | `claude_code_code_edit_tool_decision_total` (label `decision=accept\|reject`) |

   → Update the panel queries in `provisioning/dashboards/claude-code-analytics.json`
   to the real names (and re-provision on the VM).

2. **Label mismatch — legends will be blank.**
   Panels use `legendFormat: "{{user}}"`, but real metrics carry `user_email`
   (no `user` label). Change legends to `{{user_email}}`.

3. **Accept/reject panel (panel-5) has no real data yet.**
   `claude_code_code_edit_tool_decision_total` only appears once a session actually
   accepts/rejects a file edit; the 3 verification sessions were read-only. Drive an
   editing session to populate it.

4. **Config drift not fully captured in git.** The VM's `otel-collector-config.yaml`
   was already ahead of the repo (Prometheus `resource_to_telemetry_conversion` +
   `add_metric_suffixes:false`); the new telemetry `settings.json` env block is VM-only.
   Decide whether to codify these (e.g. a documented `settings.json` template).

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
