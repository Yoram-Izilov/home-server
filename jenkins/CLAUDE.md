# jenkins/CLAUDE.md

The Jenkins controller for the home server. It runs the CI/CD pipelines for every repo (the Discord bot, this monitoring stack, future services). It is the one thing **not** deployed by a pipeline — bring it up by hand.

## Architecture

- `jenkins` — built from `Dockerfile` (`jenkins/jenkins:jdk21` + the Docker CLI, `rsync`, and the compose v2 plugin). UI on host `:8888` (→ 8080), agent port `:50000`. Config/jobs persist in the `jenkins-data` named volume.
- `socat` — exposes the host `/var/run/docker.sock` over TCP `2376`. Jenkins reaches it via `DOCKER_HOST=tcp://socat:2376`.

So every `docker` / `docker compose` command in a pipeline runs against the **host** daemon, not a daemon inside the Jenkins container.

## The same-path bind-mount rule (important)

Because pipelines drive the host daemon, the Jenkins container's own filesystem (e.g. `/var/jenkins_home/workspace/...`) is **invisible** to that daemon. Two consequences:

1. **Any host path a pipeline deploys to must be bind-mounted into this container at the identical path.** A deploy does `rsync → $PATH` (writes inside Jenkins) then `docker compose -f $PATH/... up -d` (host daemon resolves the compose file's relative mounts against the host). Only a same-path bind mount makes those the same directory. Current mounts:
   - `/home/izilov/Desktop/discord-files` — bot runtime data (`DISCORD_DATA_PATH`).
   - `/home/izilov/Desktop/home-server-monitoring` — monitoring deploy target (`MONITORING_DEPLOY_PATH` in the repo-root `Jenkinsfile`). **If you change `MONITORING_DEPLOY_PATH`, change this volume to match, and recreate the container.**

2. **Don't bind-mount the workspace into a sibling container** — it resolves to an empty dir on the host. The monitoring `Jenkinsfile` validates configs with `docker cp` into a throwaway container instead (streams over the API, works regardless of the host/agent split).

## Operating

```bash
docker compose up -d --build   # first run, or after editing the Dockerfile
docker compose up -d           # start with the existing image
```

Editing the `Dockerfile` (e.g. adding a CLI tool a pipeline needs) requires `--build` **and** recreating the container.

## Credentials

Pipeline secrets are stored as Jenkins "secret text" credentials, referenced by ID from each `Jenkinsfile` (e.g. `grafana-admin-password`, `discord-alertmanager-webhook-url`). They live in `jenkins-data`, never in this repo.
