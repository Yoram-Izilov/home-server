---
name: sync-monitoring-config
description: Read-only audit of the monitoring stack for drift -- checks that every scraped service has a target, rule_files globs resolve, Grafana datasource URLs match compose service:port, the alertmanager target matches, images are pinned, and the -p monitoring network invariant holds. Use when asked to verify monitoring config, or after editing anything under monitoring/.
---

# Sync monitoring config

`CLAUDE.md` and `monitoring/CLAUDE.md` list invariants that must agree across `monitoring/docker-compose.yml`, `prometheus/prometheus.yml`, the rule files, `alertmanager/alertmanager.yml`, and the Grafana provisioning. This skill reads them and flags drift. It is **read-only** - it does not modify files.

## What to check

| Check | Where to look | Expected |
|---|---|---|
| Scrape target ↔ service | `prometheus/prometheus.yml` `scrape_configs`, `docker-compose.yml` `services:` | Every in-stack scrape job (`prometheus`, `loki`, `tempo`, `grafana`, `alertmanager`, `otel-collector`) maps to a service. `node-exporter` is scraped at `host.docker.internal:9100` (it's `network_mode: host`). `postgres-exporter:9187` is external (lives in `discord-py`) - flag as expected-external, not missing. |
| Rule files resolve | `prometheus.yml` `rule_files:`, `prometheus/rules/` | The `/etc/prometheus/rules/*.yml` glob has at least one matching file; every file is valid (see `promtool check rules`). |
| Loki ruler | `loki/loki-config.yaml` `ruler:`, `loki/rules/fake/` | `alertmanager_url` points at `http://alertmanager:9093`; rule files exist. |
| Grafana datasources | `grafana/provisioning/datasources/datasources.yaml` | Each datasource URL host:port matches a real service: `prometheus:9090`, `loki:3100`, `tempo:3200`, `alertmanager:9093`, `pyroscope:4040`. |
| Dashboards path | `grafana/provisioning/dashboards/dashboards.yaml`, `docker-compose.yml` grafana volume | Provider `path:` (`/var/lib/grafana/dashboards`) matches the mounted `./grafana/dashboards` volume. |
| Alertmanager wiring | `prometheus.yml` `alerting.alertmanagers`, `docker-compose.yml` | Target `alertmanager:9093` matches the `alertmanager` service + published port. |
| Webhook not inlined | `alertmanager/alertmanager.yml` | Uses `webhook_url_file: /etc/alertmanager/discord-webhook-url`, never a literal `https://discord.com/...` URL. |
| Images pinned | `docker-compose.yml` all `image:` | Every image has an explicit version tag; none use `:latest` or an untagged image. |
| Network invariant | `docker-compose.yml` `networks:` | Network is named `monitoring` (becomes `monitoring_monitoring` under `-p monitoring`). It must not be renamed - the bot attaches to `monitoring_monitoring` externally. |

## How to run

1. Read `monitoring/docker-compose.yml`, `prometheus/prometheus.yml`, `prometheus/rules/` (list files), `loki/loki-config.yaml`, `grafana/provisioning/datasources/datasources.yaml`, `grafana/provisioning/dashboards/dashboards.yaml`, and `alertmanager/alertmanager.yml`.
2. Build a markdown table: one row per check, columns = check / actual / expected / OK?.
3. Call out every mismatch with the specific fix. Treat `postgres-exporter` and `node-exporter` as expected-external/host (not drift).
4. If everything agrees, say so plainly: "all monitoring config is in sync, no drift detected".

## Output format

A markdown table plus a short prose section listing drift with suggested fixes. Don't modify files - this is an audit only. If the user wants the drift fixed, they'll ask.

## Why this matters

The stack fails silently when config drifts. A scrape job pointing at a renamed/removed service shows as a perpetually-down target but never errors at deploy. A Grafana datasource URL that doesn't match a service:port makes a whole dashboard render "No data" with no obvious cause. An unpinned image means a `docker compose pull` can swap in a breaking major version on the next deploy. And renaming the `monitoring` network - or dropping `-p monitoring` - quietly detaches the bot, so traces and profiles vanish from Tempo and Pyroscope with no error anywhere.
