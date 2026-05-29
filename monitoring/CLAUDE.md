# monitoring/CLAUDE.md

Guidance for the monitoring stack. The repo-root `CLAUDE.md` covers `home-server` as a whole; this file loads when something under `monitoring/` is being edited.

This stack used to live inside the `discord-py` repo. It now lives here, in `home-server`, as the single source of truth — but the deployed network name is unchanged (`monitoring_monitoring`), so the bot keeps tracing without any change on its side.

## Stack

All services are defined in `docker-compose.yml` and joined to the `monitoring` network. When deployed with `docker compose -p monitoring`, that network resolves to `monitoring_monitoring`, which the `discord-py` bot's root compose attaches to as `external: true`.

| Service | Image | Purpose |
|---|---|---|
| `prometheus` | `prom/prometheus:v3.11.3` | Metrics. Rules in `prometheus/rules/`. Remote-write receiver enabled. |
| `node-exporter` | `prom/node-exporter:v1.11.1` | Host metrics. Uses `network_mode: host`. |
| `grafana` | `grafana/grafana:13.0.1` | UI. Provisioning + dashboards mounted from `grafana/`. |
| `loki` | `grafana/loki:3.7.2` | Logs. Rules in `loki/rules/fake/`. |
| `promtail` | `grafana/promtail:3.4.1` | Log shipper. Reads `/var/lib/docker/containers` and `/var/log`. |
| `tempo` | `grafana/tempo:2.10.5` | Traces. Receives OTel on `4317`. |
| `otel-collector` | `otel/opentelemetry-collector-contrib:0.111.0` | OTel gateway. Exposes `4317`/`4318`. |
| `alertmanager` | `prom/alertmanager:v0.28.1` | Alerts → Discord webhook. |
| `pyroscope` | `grafana/pyroscope:1.10.0` | Continuous profiling. Bot pushes to `http://pyroscope:4040`. |
| `blackbox-exporter` | `prom/blackbox-exporter:v0.27.0` | Black-box HTTP/TLS uptime probes. Config in `blackbox/blackbox.yml`. Scraped via the `blackbox-portfolio` job in `prometheus.yml`. |

`postgres-exporter` runs in the **`discord-py`** root `docker-compose.yml` (not here) and is scraped by this Prometheus at `postgres-exporter:9187` over the shared `monitoring_monitoring` network.

The bot exports traces to `tempo:4317` (hardcoded in the bot's `bot.py`) and profiles to `http://pyroscope:4040`.

> Some bundled dashboards/rules are still bot-specific (`grafana/dashboards/discord-bot.json`, `prometheus/rules/app.yml`, `loki/rules/fake/bot.yml`, `prometheus/rules/postgres.yml`). They came along with the move and stay valid because the bot still scrapes/traces into this stack. Treat them as monitoring assets for the bot service, alongside the host/stack/postgres rules.

### Portfolio assets

The `portfolio` site (a separate repo) is monitored entirely from here, with no scrape target of its own:

- **Logs/visitors** — the `portfolio` container logs structured JSON access lines to stdout, which Promtail already ships to Loki via Docker SD (`{container="portfolio"}`). No Promtail change is needed.
- **Recording rules + alert** — `loki/rules/fake/portfolio.yml` computes `portfolio:unique_visitors:1d` / `portfolio:requests:1d` and a `Portfolio5xxSpike` alert. The recording rules are remote-written to Prometheus (see the ruler `remote_write` block in `loki/loki-config.yaml`) so they outlive Loki's 7d retention and feed the "all-time" dashboard panels.
- **Uptime/TLS** — the `blackbox-portfolio` Prometheus job probes `https://www.yoram-izilov.com`; `prometheus/rules/portfolio.yml` alerts on `PortfolioDown` / `PortfolioCertExpiringSoon` / `PortfolioSlowResponse`.
- **Tracing** — the portfolio nginx ships per-request spans (`service.name=portfolio`) to `otel-collector:4317`. For this to resolve, the `portfolio` container joins **`monitoring_monitoring`** in addition to `nginx_nginx_network` (the "needs observability + routing → both networks" pattern). Tempo's `metrics_generator` then produces span-metrics + a service map automatically.
- **Dashboard** — `grafana/dashboards/portfolio.json` ("Portfolio — Traffic & Health", uid `portfolio-traffic`).

## Deploy flow

The repo-root `Jenkinsfile` deploys the stack (Deploy → Remove Dangling Images → Verify). The deploy step:

1. `rsync -a --delete monitoring/` → `MONITORING_DEPLOY_PATH` (`/home/izilov/Desktop/home-server-monitoring`)
2. Writes the Discord webhook secret to `alertmanager/discord-webhook-url` (gitignored)
3. `docker compose -p monitoring -f "$MONITORING_DEPLOY_PATH/docker-compose.yml" up -d`

The `-p monitoring` flag pins the project name so the network resolves to `monitoring_monitoring` — the name the bot's root compose expects to attach to as `external: true`. **Do not remove `-p monitoring`** and do not rename the network.

## Credentials (Jenkins secret-text)

| Credential ID | Used as | Consumed by |
|---|---|---|
| `grafana-admin-password` | env `GRAFANA_ADMIN_PASSWORD` | Grafana via `GF_SECURITY_ADMIN_PASSWORD` |
| `discord-alertmanager-webhook-url` | written to `alertmanager/discord-webhook-url` | Alertmanager via `webhook_url_file:` |

For local dev: put `GRAFANA_ADMIN_PASSWORD=...` in `monitoring/.env` and the Discord webhook URL in `monitoring/alertmanager/discord-webhook-url`. Both are gitignored.

## Alertmanager Discord webhook

`alertmanager.yml` references the webhook via `webhook_url_file: /etc/alertmanager/discord-webhook-url` — never inline the URL into the YAML. The file is bind-mounted read-only into the container.

## Host-path gotcha (Jenkins)

Jenkins runs inside a container but talks to the **host** Docker daemon, so the bind-mount paths in `docker-compose.yml` (`./prometheus/prometheus.yml`, etc.) are resolved by the host, not by the Jenkins container. That's why the deploy rsyncs the whole `monitoring/` tree to `MONITORING_DEPLOY_PATH` on the host and runs compose from there.

For this to work, the Jenkins container itself must have `MONITORING_DEPLOY_PATH` bind-mounted at the **same path** (so `docker compose -f /home/izilov/...` inside Jenkins points at the same file the host daemon resolves mounts against). `rsync` must be installed in the Jenkins image. **If you change `MONITORING_DEPLOY_PATH` in the `Jenkinsfile`, update the Jenkins container's bind mount to match.**

## When editing files here

- Touching a Prometheus rule, Grafana dashboard, Tempo config, etc. only requires a redeploy — push to a branch, open a PR; merging to `main` triggers the deploy. Lint locally first (`promtool`/`amtool`, see the repo-root CLAUDE.md) — the pipeline no longer does it for you.
- Adding a new monitored service: run `/add-monitored-service`. It adds the scrape target, scaffolds starter alert rules, and reminds you the service must join `monitoring_monitoring`.
- Auditing for drift: run `/sync-monitoring-config`.
- Changing the network name or removing `-p monitoring`: breaks the bot's `monitoring_monitoring` external attachment. Don't.
