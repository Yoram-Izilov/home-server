# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`home-server` is the central infrastructure repo for the self-hosted box that runs at `yoram-izilov.com`. It owns the shared services that the application repos depend on - not the apps themselves.

**Today** it holds the **monitoring stack** (`monitoring/`) and the **Jenkins controller** (`jenkins/`) that runs CI/CD for every repo. The Discord bot (`discord-py`) and the portfolio site (`portfolio`) live in their own repos and *consume* infrastructure defined here.

**Planned** (documented, not yet built - see [Planned structure](#planned-structure)): the host **nginx** reverse proxy will move in here too, so all shared infra lives in one place.

There is no application code and no test suite here - everything is declarative config (Docker Compose, Prometheus rules, Grafana dashboards, Alertmanager routing). Verify changes by validating configs and bringing the stack up; see [Verifying changes](#verifying-changes).

## Running locally

```bash
# from monitoring/
cd monitoring

# secrets (gitignored): admin password + the Discord alert webhook
echo 'GRAFANA_ADMIN_PASSWORD=changeme' > .env
printf '%s' 'https://discord.com/api/webhooks/...' > alertmanager/discord-webhook-url

# bring the stack up - the -p monitoring project name is REQUIRED (see below)
docker compose -p monitoring up -d
```

Then: Grafana → http://localhost:3000, Prometheus → http://localhost:9090, Alertmanager → http://localhost:9093.

## Deployment

`Jenkinsfile` deploys the monitoring stack:

1. **Deploy** - `rsync -a --delete monitoring/` to `MONITORING_DEPLOY_PATH` on the host, writes the webhook secret to `alertmanager/discord-webhook-url`, then `docker compose -p monitoring -f .../docker-compose.yml up -d`.
2. **Remove Dangling Images** - prunes leftover image layers.
3. **Verify** - asserts `prometheus`, `grafana`, `alertmanager`, `loki`, `tempo` containers are running.

Config linting is **not** part of the pipeline - validate locally before pushing (see [Verifying changes](#verifying-changes) or run `/sync-monitoring-config`).

### Invariants - do not break these

- **`-p monitoring` is mandatory.** It pins the Compose project name so the network resolves to `monitoring_monitoring`. The `discord-py` bot attaches to that exact name as an `external` network to reach `tempo:4317` and `pyroscope:4040`. Rename it and the bot silently stops tracing.
- **Pin every image.** Every service uses an exact tag (e.g. `prom/prometheus:v3.11.3`), never `:latest`. Reproducible deploys only.
- **Never inline the webhook URL.** `alertmanager.yml` reads it via `webhook_url_file:`; the secret is injected at deploy time, never committed.
- **Host-path gotcha.** Jenkins runs in a container but drives the *host* Docker daemon, so the bind-mount paths in `monitoring/docker-compose.yml` are resolved by the host. That's why deploy rsyncs the tree to `MONITORING_DEPLOY_PATH` and runs Compose from there. The Jenkins container must bind-mount that path at the **same** location, and `rsync` must be in the Jenkins image. **If you change `MONITORING_DEPLOY_PATH`, update the Jenkins container's bind mount to match.**

### Jenkins credentials (secret text)

| Credential ID | Used as | Consumed by |
|---|---|---|
| `grafana-admin-password` | env `GRAFANA_ADMIN_PASSWORD` | Grafana via `GF_SECURITY_ADMIN_PASSWORD` |
| `discord-alertmanager-webhook-url` | written to `alertmanager/discord-webhook-url` | Alertmanager via `webhook_url_file:` |

## Stack

Eleven services, all defined in `monitoring/docker-compose.yml` on the `monitoring` network. Detailed guidance lives in `monitoring/CLAUDE.md`.

| Service | Image | Port | Purpose |
|---|---|---|---|
| `prometheus` | `prom/prometheus:v3.11.3` | 9090 | Metrics + alert rule evaluation. Rules in `prometheus/rules/`. |
| `node-exporter` | `prom/node-exporter:v1.11.1` | host | Host system metrics (`network_mode: host`). |
| `grafana` | `grafana/grafana:13.0.1` | 3000 | Dashboards + datasources, provisioned from `grafana/`. |
| `loki` | `grafana/loki:3.7.2` | 3100 | Log aggregation. Log-based rules in `loki/rules/fake/`. |
| `promtail` | `grafana/promtail:3.4.1` | - | Ships Docker + `/var/log` logs to Loki. |
| `tempo` | `grafana/tempo:2.10.5` | 3200 | Trace storage. Receives OTel on 4317. |
| `otel-collector` | `otel/opentelemetry-collector-contrib:0.111.0` | 4317/4318 | OTel gateway → Tempo. |
| `alertmanager` | `prom/alertmanager:v0.28.1` | 9093 | Routes alerts → Discord webhook. |
| `pyroscope` | `grafana/pyroscope:1.10.0` | 4040 | Continuous profiling. |
| `blackbox-exporter` | `prom/blackbox-exporter:v0.27.0` | - | Black-box HTTP/TLS uptime probe of the public site. |
| `alloy` | `grafana/alloy:v1.10.0` | - | eBPF profiler for the portfolio nginx (`privileged` + `pid: host`). |

`postgres-exporter` is **not** here - it lives in `discord-py`'s root compose (it's the bot's database) and joins `monitoring_monitoring`, where this Prometheus scrapes it at `postgres-exporter:9187`.

## Planned structure

As shared services move in, the repo will grow to:

```
home-server/
  monitoring/      ← observability stack (built - see monitoring/CLAUDE.md)
  jenkins/         ← Jenkins controller compose + Dockerfile (built - see jenkins/CLAUDE.md)
  nginx/           ← PLANNED: host reverse proxy, *.yoram-izilov.com subdomain routing
```

Two external Docker networks tie the box together. Apps join them; `home-server` owns them:

- **`monitoring_monitoring`** - created by `docker compose -p monitoring`. The bot joins it to emit traces/profiles.
- **`nginx_nginx_network`** - the host nginx network. The `portfolio` container (and future services) join it; nginx proxies `www.yoram-izilov.com` → `http://portfolio:80/` by container name. The reverse-proxy config currently sampled in `portfolio/deploy/nginx-reverse-proxy.conf` is what will move into `nginx/` here.

When adding a service that should be both reverse-proxied and monitored, it joins **both** networks.

## Secrets

Never commit these (they're gitignored):

- `monitoring/.env` - holds `GRAFANA_ADMIN_PASSWORD`.
- `monitoring/alertmanager/discord-webhook-url` - the Discord alert webhook.
- Any `*.key`, `*.pem`, `*-webhook-url`, `*.htpasswd`.

In production these come from Jenkins credentials; locally they're plain files you create by hand. The `block-sensitive-files` hook blocks `git add` of them.

## Git guidelines

### Commit message format

```
<type>(<scope>): <short summary in imperative mood>

[optional body - wrap at 72 chars]
```

**Types:** `feat` · `fix` · `refactor` · `chore` · `docs` · `style`

**Scopes** - match the area changed: `monitoring`, `prometheus`, `grafana`, `loki`, `tempo`, `promtail`, `alertmanager`, `pyroscope`, `compose`, `jenkins`, `nginx`, `docs`

**Examples**

```
# Good
feat(prometheus): add scrape target + alerts for the portfolio container
fix(alertmanager): correct Discord webhook grouping interval
chore(compose): bump grafana to 13.0.1

# Bad
update config
fix stuff
```

The `verify-commit-message` hook enforces this format (blocks on mismatch).

### Discipline

- **One logical change per commit** - keep `git revert` safe on each one.
- **Work on a branch** (`feat/<slug>`, `fix/<slug>`, `chore/<slug>`), open a PR, never push directly to `main` or force-push it.
- Never commit secrets (see [Secrets](#secrets)).

## Verifying changes

```bash
# config parses
docker compose -p monitoring -f monitoring/docker-compose.yml config >/dev/null

# rules + alertmanager lint (same checks the Jenkinsfile runs)
docker run --rm -v "$PWD/monitoring/prometheus:/etc/prometheus:ro" --entrypoint sh \
  prom/prometheus:v3.11.3 -c 'promtool check config /etc/prometheus/prometheus.yml && promtool check rules /etc/prometheus/rules/*.yml'
docker run --rm -v "$PWD/monitoring/alertmanager:/cfg:ro" --entrypoint amtool \
  prom/alertmanager:v0.28.1 check-config /cfg/alertmanager.yml

# bring it up and confirm targets are healthy at http://localhost:9090/targets
docker compose -p monitoring up -d
```

Run `/sync-monitoring-config` to audit the stack for drift (missing scrape targets, dangling rule files, unpinned images, broken datasource URLs).
