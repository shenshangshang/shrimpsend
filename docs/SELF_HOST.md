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

Production runs the **server stack in Docker** via `./scripts/deploy.sh` (MySQL + WuKongIM + Spring Boot). The Next.js web app still runs on the host as a Node standalone process. Secrets live in an **ops** config directory (see [ops/README.md](../ops/README.md)).

### One-time server setup

1. Clone the public app repo and an ops config repo **as siblings**:

```bash
git clone git@github.com:shrimpsend/shrimpsend.git shrimpsend
cd shrimpsend

# Self-hosters: public samples (replace placeholders before production)
git clone git@github.com:shrimpsend/public-ops.git ../ops

# Maintainers: private production ops (requires access)
# git clone git@github.com:shrimpsend/ops.git ../ops
```

2. Optional: `export ULTRASEND_OPS_DIR=/path/to/your-ops` if ops is not at `../ops`.
3. Ensure **Docker** and **Node.js 20+** are available on the server. Java and a host MySQL install are not required. Do not expose WuKongIM HTTP API port 5001 publicly (Compose binds it to `127.0.0.1`).

Scripts resolve ops in this order: `ULTRASEND_OPS_DIR` → sibling `../ops` → validate `.ultrasend-ops` marker and at least one config subdirectory (`cn/`, `overseas/`, `local/`, etc.).

### Deploy (interactive)

```bash
./scripts/deploy.sh
```

The script may:

- Pull latest git (confirm at prompt)
- Ask **China (xiachuan)** vs **Overseas (ShrimpSend)** cluster
- Optionally sync from ops (`sync-to-build-machine.sh`)
- Build backend Docker image and Next.js standalone Web
- Restart Docker server stack (MySQL 3306, WuKongIM 5200, backend 9000) and Web (3000)

You can run `scripts/sync-to-build-machine.sh` before `deploy.sh`; the deploy script can sync again when prompted.

### Deploy (non-interactive)

China (default):

```bash
SPRING_PROFILE=prod CLUSTER_LABEL='China (xiachuan)' ./scripts/deploy.sh
```

Overseas:

```bash
SPRING_PROFILE=prod-overseas CLUSTER_LABEL='Overseas (ShrimpSend)' ./scripts/deploy.sh
```

Overseas Web builds with `NEXT_PUBLIC_STRIPE_BILLING=live` automatically.

### Operations

```bash
./scripts/deploy.sh stop
./scripts/deploy.sh status
./scripts/deploy.sh logs
```

### Spring profiles (reference)

| Profile | Use case |
|---------|----------|
| (default) | Local dev — China logic |
| `dev-overseas` | Local dev — ShrimpSend logic (`start-dev.sh --overseas`) |
| `prod` | China production (`application-prod.yml` from ops) |
| `prod-overseas` | ShrimpSend production |

### Environment variables (backend)

See [backend/.env.example](../backend/.env.example). Critical production values:

- `SPRING_DATASOURCE_*` — database
- `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`
- `APP_MESSAGES_ENCRYPTION_KEY_BASE64` — AES-GCM key for legacy cloud-stored message text (`enc:v1:`)
- `APP_USER_DATA_ENCRYPTION_KEK_BASE64` — server KEK wrapping per-user DEKs (S3 SK, new message text `enc:u:v1:`)
- `APP_USER_DATA_ENCRYPTION_MIGRATE_S3_ON_STARTUP` / `APP_USER_DATA_ENCRYPTION_MIGRATE_MESSAGES_ON_STARTUP` — one-shot migration switches
- `WUKONGIM_API_URL`, `WUKONGIM_WS_PUBLIC_URL` — WuKongIM internal API and public WebSocket URL
- `REALTIME_BUS` — `wukongim` (default) or `centrifugo` rollback
- `ALIPAY_*` — China payments (optional overseas)
- `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` — overseas
- `REVENUECAT_WEBHOOK_AUTH`
- `TENCENT_SMS_*` — China SMS (optional)
- `HOSTED_S3_*`, `STORAGE_S3_*` — object storage

## Configuration layers

| Layer | Public repo | Your secrets |
|-------|-------------|--------------|
| Local dev (team) | `*.example` templates | `ops/local/` → `./scripts/deploy-local.sh` |
| Local dev (minimal) | `config.json`, `application.yml` | `./scripts/setup-local-config.sh` |
| Docker | `.env` from `.env.example` | Local `.env` (or `ops/local/docker.env`) |
| Web | `web/.env.example` | `web/.env.local` (sync from `ops/web/.env.local`) |
| Flutter OpenPanel | `openpanel_env.secrets.example.dart` | `openpanel_env.secrets.dart` (gitignored) |
| Flutter RC / prod URLs | `env.secrets.example.dart` | `env.secrets.dart` (gitignored) |
| Production | `*.example.yml`, `config.prod.example.bare.json` | [public-ops](https://github.com/shrimpsend/public-ops) samples or private ops → `sync-to-build-machine.sh` |

## Docker server stack

MySQL + WuKongIM + backend run in Compose. Web is not included (use `./scripts/start-dev.sh` or `cd web && npm run dev`).

```bash
./scripts/setup-local-config.sh   # creates .env and backend/.env from examples
docker compose up -d              # MySQL :3306, WuKongIM :5200/:5001, backend :9000
```

## Flutter / mobile builds

Official release builds read RevenueCat public keys, production API/WS URLs, and OpenPanel client ids from gitignored `app/lib/config/env.secrets.dart` and `openpanel_env.secrets.dart` (synced from `ops/flutter/`). See `app/lib/config/env.dart` for dart-define overrides.

```bash
# iOS cn / intl (on macOS)
cd app && ./scripts/package_ios.sh --all
```

HarmonyOS: copy `build-profile.example.json5` → `build-profile.json5` or sync from ops.

## China realtime (WuKongIM on the API host)

Official CN clients connect to **`wss://api.xiachuan.net/wkws`** (same host as the REST API). Nginx must reverse-proxy `/wkws/` to WuKongIM `:5200` with WebSocket `Upgrade` and a long `proxy_read_timeout`. Keep the WuKongIM HTTP API (`:5001`) on localhost / docker network only.

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
