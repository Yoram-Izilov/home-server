---
name: add-monitored-service
description: Wire a new service into the monitoring stack end-to-end -- adds a Prometheus scrape job to prometheus/prometheus.yml, scaffolds starter alert rules in prometheus/rules/<svc>.yml using the existing severity/summary/description convention, and reminds that the service must join the monitoring_monitoring network. Use when asked to monitor, scrape, or add alerts for a new service.
---

# Add monitored service

Use this skill when the user wants Prometheus to scrape a new service and alert on it.

## What to collect from the user

1. **Service name** — the Prometheus `job_name` and rule-file slug (kebab-case, e.g. `portfolio`, `nginx`).
2. **Metrics endpoint** — `host:port` Prometheus should scrape (default path `/metrics`). For a container on `monitoring_monitoring`, this is `<container_name>:<port>`. For something on the host, use `host.docker.internal:<port>`.
3. **Where it runs** — in `monitoring/docker-compose.yml`, in another repo's compose (like the bot's `postgres-exporter`), or on the host. This determines networking, not the scrape syntax.
4. **Dashboard?** — whether to also drop a starter Grafana dashboard JSON.

Ask via AskUserQuestion if any of these are ambiguous. Don't proceed with placeholders.

## Steps to execute

1. **Confirm the job doesn't already exist** — grep `prometheus/prometheus.yml` for `job_name: '<name>'`.
2. **Add the scrape job** to `prometheus/prometheus.yml` under `scrape_configs:`, matching the existing two-space style:
   ```yaml
     - job_name: '<name>'
       static_configs:
         - targets: ['<host:port>']
   ```
3. **Scaffold alert rules** in `prometheus/rules/<name>.yml`. Match the convention in `prometheus/rules/alerts.yml` exactly — `severity` label (`critical` | `warning`), `summary` + `description` annotations with `{{ $labels.* }}` / `{{ $value }}` templating, and a `for:` duration. Always include a "down" alert:
   ```yaml
   groups:
     - name: <name>
       interval: 30s
       rules:
         - alert: <Name>Down
           expr: up{job="<name>"} == 0
           for: 2m
           labels:
             severity: critical
           annotations:
             summary: "<name> target is down"
             description: "{{ $labels.instance }} (job <name>) has been down for more than 2 minutes."
   ```
   Add service-specific warning rules (latency p95, error rate, saturation) when the user names concrete SLOs — don't invent thresholds.
4. **Confirm networking.** Remind the user: a scrape target only resolves if the service is reachable from Prometheus. A container must join the `monitoring_monitoring` network (`networks: [..., monitoring]` with that network declared `external: true` in its own compose). The new rule file is picked up automatically by the `rule_files: /etc/prometheus/rules/*.yml` glob — no edit to `prometheus.yml` needed for rules.
5. **(Optional) Dashboard.** If requested, add `grafana/dashboards/<name>.json`. The provisioning provider already loads everything in that folder, so no provisioning edit is needed.
6. **Tell the user the verification steps:**
   - Lint: `docker run --rm -v "$PWD/monitoring/prometheus:/etc/prometheus:ro" --entrypoint sh prom/prometheus:v3.11.3 -c 'promtool check config /etc/prometheus/prometheus.yml && promtool check rules /etc/prometheus/rules/*.yml'`
   - Redeploy locally: `docker compose -p monitoring up -d` (or merge to `main` for Jenkins).
   - Confirm the target is `up` at http://localhost:9090/targets and the rules load at http://localhost:9090/rules.

## What NOT to do

- Don't invent alert thresholds. A "down" alert is always safe; latency/error thresholds need real SLOs from the user.
- Don't add the target with an unpinned or wrong port. A typo here shows as a perpetually-down target, never an error.
- Don't put the new service's container definition in `monitoring/docker-compose.yml` unless it's genuinely part of the observability stack. App containers stay in their own repo's compose and just join `monitoring_monitoring`.
- Don't rename or re-scope the `monitoring` network to reach the new service — every monitored container shares `monitoring_monitoring`.
- Don't write the user's commit. Let them review the diff; if asked, use scope `prometheus` (or `grafana` for a dashboard-only change).
