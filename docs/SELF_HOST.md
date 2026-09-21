# Self-Hosting Guide

This document describes how to run ShrimpSend / 虾传 on your own infrastructure.

Chinese setup guide (including troubleshooting): [docs/README.zh-CN.md](README.zh-CN.md)

## Architecture

| Component | Default port | Notes |
|-----------|--------------|-------|
| MySQL 8 | 3306 | Primary database |
| WuKongIM | 5200 (WS), 5001 (internal API) | Real-time control plane |
| Spring Boot backend | 9000 | REST API |
| Next.js web | 3000 | Web client |

## Local development

All local stacks use `./scripts/start-dev.sh` to start the **Docker server stack** (MySQL, WuKongIM, Spring Boot) plus the host Web app. Stop with `./scripts/stop-dev.sh`. Logs: `scripts/logs/` and `docker compose logs`.

### China logic (default profile)

**Maintainers** (private `ops/local/`):

```bash
chmod +x scripts/deploy-local.sh scripts/start-dev.sh scripts/stop-dev.sh
./scripts/deploy-local.sh    # sync ops/local（库由 Compose MySQL 首次启动创建）
./scripts/start-dev.sh
```

**Contributors** (examples only):

```bash
chmod +x scripts/setup-local-config.sh scripts/start-dev.sh scripts/stop-dev.sh
./scripts/setup-local-config.sh
./scripts/start-dev.sh
```

MySQL now runs in Compose (`ultrasend` and `ultrasend_overseas` are created on first volume init). You do not need a host MySQL install.

### Overseas / ShrimpSend logic (`dev-overseas`)

Same config step as above. Database: `ultrasend_overseas` (created by Compose on first MySQL volume init, and re-ensured when the stack starts).

```bash
./scripts/start-dev.sh --overseas
# Stop: ./scripts/stop-dev.sh
```

Stripe webhook (separate terminal, for membership testing):

```bash
stripe listen --forward-to localhost:9000/api/membership/stripe/webhook
```

**Backend only** (no Web): `backend/scripts/run-dev-overseas.sh` (same Docker server stack, `dev-overseas` profile).

## Production deployment

Production uses **four Docker containers**: MySQL, WuKongIM, Spring Boot and Next.js Web. Operators edit **one file**, `.env.production`; the server needs Docker Engine with Compose v2 (supporting `up --wait`), not host Java or Node. HTTPS is terminated by your existing reverse proxy.

### First deployment

```bash
cp .env.production.example .env.production
chmod 600 .env.production
# Edit .env.production: replace example.com and fill every required secret.
./scripts/deploy.sh check
./scripts/deploy.sh up
./scripts/deploy.sh status
```

`check` validates Compose without printing expanded secrets. `up` builds both application images before updating containers, then waits for all health checks. It does not pull Git, copy ops files, delete volumes, or terminate host processes. A failed startup exits nonzero; it does not automatically roll back containers.

Generate each JWT / IM secret separately with `openssl rand -hex 32`, and each AES key with `openssl rand -base64 32`. For an **existing installation**, preserve the original encryption keys and database credentials. Changing keys without a migration can make stored data unreadable.

For a config outside the checkout, use the same setting for every command:

```bash
DEPLOY_ENV_FILE=/etc/shrimpsend/production.env ./scripts/deploy.sh up
DEPLOY_ENV_FILE=/etc/shrimpsend/production.env ./scripts/deploy.sh status
```

Do not `source` the env file. Use Compose env syntax; put values containing literal `$` in single quotes. Shell environment variables take precedence over Compose interpolation, so remove stale deployment exports from the calling shell. No fallback credentials are exported by the new script.

### Configuration map

| Settings in `.env.production` | Purpose |
|---|---|
| `COMPOSE_PROJECT_NAME` | Stable identity for containers, network and volumes; keep it unchanged on redeploy |
| `SPRING_PROFILES_ACTIVE`, `MYSQL_DATABASE` | China: `prod` / `ultrasend`; overseas: `prod-overseas` / `ultrasend_overseas` |
| `MYSQL_ROOT_PASSWORD`, `MYSQL_USER`, `MYSQL_PASSWORD` | MySQL initialization and backend access |
| `WUKONGIM_MANAGER_TOKEN`, `WUKONGIM_WS_PUBLIC_URL` | Shared internal IM token and browser/App reachable WS address |
| `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET` | Account authentication |
| `APP_MESSAGES_ENCRYPTION_KEY_BASE64`, `APP_USER_DATA_ENCRYPTION_KEK_BASE64` | Persistent data encryption; back these up separately with the database |
| `APP_PUBLIC_WEB_BASE_URL`, `APP_CORS_ALLOWED_ORIGINS` | Public site URL and allowed browser origins |
| `NEXT_PUBLIC_API_URL`, `NEXT_PUBLIC_WUKONGIM_WS_URL`, `NEXT_PUBLIC_WEB_BASE_URL` | Explicit browser-facing endpoints; never use Docker service names here |
| `BIND_ADDRESS`, `WEB_PORT`, `API_PORT`, `WUKONGIM_WS_PORT` | Host proxy upstreams, default `127.0.0.1:3000/9000/5200` |
| `NEXT_PUBLIC_OPENPANEL_WEB_CLUSTER` | `cn` or `intl` for existing release/analytics cluster selection |
| Mail/SMS, Alipay, Stripe, RevenueCat, S3 variables | Optional integrations; copy required values from your previous configuration |

Backend receives the env file at runtime. `docker/production.yml` is a checked-in mapping with production defaults, mounted read-only outside the JAR; it is not another per-server secrets file. Local ops-synced production YAML files are excluded from the production backend build. Base schema behavior remains `ddl-auto=update`; back up before upgrading an existing database.

The Web image receives only explicitly listed `NEXT_PUBLIC_*` build arguments, not the backend env file. All `NEXT_PUBLIC_*` values are public browser data, including the existing analytics fields. Do not put backend credentials there. Next.js freezes these values at build time: run **`up` after changing them**. See [Next.js environment variables](https://nextjs.org/docs/app/guides/environment-variables) and [Docker environment interpolation](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/).

Changing backend-only runtime values can use `./scripts/deploy.sh apply` (no build, images must already exist). For changed mounted file contents alone, restart the backend so Spring reloads it:

```bash
docker compose --env-file .env.production -f compose.production.yml restart backend
```

### HTTPS routing

Configure your reverse proxy:

| Public route | Host upstream |
|---|---|
| `https://example.com/` | `http://127.0.0.1:3000` |
| `https://api.example.com/api/` | `http://127.0.0.1:9000` (preserve `/api/`) |
| `wss://api.example.com/wkws` | `http://127.0.0.1:5200/`, with WebSocket Upgrade and long read timeout |

Use [nginx-api-wukongim.example.conf](nginx-api-wukongim.example.conf) for API/WS routing and your existing certificate setup. MySQL and the IM management API are only reachable inside the production Compose network. IM callbacks use internal `http://backend:9000` addresses. Configure any optional webhook authentication consistently with your IM installation.

### Operations

```bash
./scripts/deploy.sh logs          # follow logs for all services
./scripts/deploy.sh logs backend  # one service
./scripts/deploy.sh status
./scripts/deploy.sh stop          # preserve volumes
./scripts/deploy.sh up            # build/update and wait until healthy
```

Compose defaults to the public WuKongIM v2 image used by the existing stack. Set `WUKONGIM_IMAGE` to a verified version/digest for reproducible releases. A failed build leaves the old stack running; a failed health check requires inspecting logs before retrying.

### Migrate an existing installation

1. Back up the existing database and encryption keys. Inspect `docker compose ls` and the existing volume names. Set `COMPOSE_PROJECT_NAME` to the **existing project name** when reusing `mysql_data` / `wukongim_data`; changing it creates a separate stack and empty volumes.
2. Consolidate existing root `.env`, `backend/.env`, production profile YAML and `web/.env.local` values into `.env.production`. Preserve the actual database name, account passwords, encryption keys, URLs, product IDs and callback configuration. Custom Spring values can use standard Spring environment variable names in the same file. No automatic conversion is performed.
3. Build and validate first. During the switch, stop the old host Web process using its existing service manager or recorded PID, then run the new deployment. Both cannot bind port 3000 simultaneously. Do not kill arbitrary processes by port.
4. Existing MySQL volumes do not re-run first-boot initialization: changing `MYSQL_DATABASE` / passwords in env does **not** create a new database, grant access or rotate users. Provision/migrate them explicitly before switching clusters.
5. Verify old history, stored S3 credentials, paired devices, guest messages and real file transfers. To revert, stop the new stack and use the previous release/config with the preserved volumes; database compatibility must be checked before downgrading.

The old host-Web workflow is retained as `scripts/deploy-legacy.sh` for migration reference. `ops/` remains useful for Flutter signing/build configuration. Production no longer requires cloning or syncing ops into application source.

## Full Docker on this workstation

For the isolated local four-container deployment, use `.env.local-deploy` and `scripts/deploy-docker-local.sh`. See [LOCAL_DOCKER.md](LOCAL_DOCKER.md) for URLs, runtime setup and restart commands.

## Local Docker development

`docker-compose.yml` and `start-dev.sh` remain the development stack: containerized MySQL + IM + backend, with host Web hot reload. They use `.env`, `backend/.env` and `web/.env.local`. The host MySQL port is **3307**, while the internal container port is 3306. Production explicitly uses `compose.production.yml` through `deploy.sh`.

```bash
./scripts/setup-local-config.sh
cd web && npm ci && cd ..
./scripts/start-dev.sh
# overseas: ./scripts/start-dev.sh --overseas
```

## Flutter / mobile builds

Official release builds read RevenueCat public keys, production API/WS URLs, and OpenPanel client ids from gitignored `app/lib/config/env.secrets.dart` and `openpanel_env.secrets.dart` (synced from `ops/flutter/`). See `app/lib/config/env.dart` for dart-define overrides.

```bash
# iOS cn / intl (on macOS)
cd app && ./scripts/package_ios.sh --all
```

HarmonyOS: copy `build-profile.example.json5` → `build-profile.json5` or sync from ops.

## China realtime (WuKongIM on the API host)

Official CN clients connect to **`wss://api.xiachuan.net/wkws`** (same host as the REST API). Nginx must reverse-proxy `/wkws` to WuKongIM `:5200` with WebSocket `Upgrade` and a long `proxy_read_timeout`. Keep the WuKongIM HTTP API (`:5001`) on localhost / docker network only.

See [nginx-api-wukongim.example.conf](nginx-api-wukongim.example.conf).

Signaling mailbox: `GET /api/mailbox/pending?deviceId=` returns ephemeral LAN/WebRTC envelopes that were missed while a device was offline (TTL ~120s). Apply `backend/scripts/migration_signaling_mailbox.sql` if `ddl-auto=update` is not used.

## Dual cluster (cn vs overseas)

| | China (xiachuan) | Overseas (ShrimpSend) |
|--|------------------|-------------------------|
| API | `api.xiachuan.net` | `api.shrimpsend.com` |
| Realtime | `wss://api.xiachuan.net/wkws` | `wss://api.shrimpsend.com/wkws` |
| Spring profile | `prod` | `prod-overseas` |
| Flutter | `--dart-define=OVERSEAS_BUILD=false`, flavor `cn` | `OVERSEAS_BUILD=true`, flavor `intl` |
| Local start | `./scripts/start-dev.sh` | `./scripts/start-dev.sh --overseas` |

## Open-sourcing note

Before publishing to GitHub, rotate all credentials that ever appeared in Git history and run [scripts/prepare-public-mirror.sh](../scripts/prepare-public-mirror.sh) to scrub history.
