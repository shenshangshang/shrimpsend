#!/usr/bin/env bash
# 本地调试一键部署：从 ops/local 同步配置（库由 Docker Compose MySQL 创建）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/scripts/sync-to-local.sh" "$@"
