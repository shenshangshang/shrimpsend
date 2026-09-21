#!/usr/bin/env bash
# Production: four containers, one external configuration file.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
case "${1:-up}" in
  help|--help|-h)
    echo "用法: ./scripts/deploy.sh [up|apply|check|stop|status|logs] [服务名]"
    echo "配置: DEPLOY_ENV_FILE=/absolute/path/to/deploy.env（默认 .env.production）"
    echo "up 构建并部署；apply 仅应用运行时配置；check 静态检查。"
    exit 0 ;;
  up|apply|check|stop|status|logs) action="${1:-up}" ;;
  *) echo "未知命令: $1" >&2; exit 2 ;;
esac
export DEPLOY_ENV_FILE="${DEPLOY_ENV_FILE:-$ROOT/.env.production}"
if [[ "$DEPLOY_ENV_FILE" != /* ]]; then
  export DEPLOY_ENV_FILE="$ROOT/$DEPLOY_ENV_FILE"
fi
if [ ! -f "$DEPLOY_ENV_FILE" ]; then
  echo "缺少配置: $DEPLOY_ENV_FILE" >&2
  echo "先 cp .env.production.example .env.production，填写域名和密钥。" >&2
  exit 1
fi
command -v docker >/dev/null 2>&1 || { echo "需要 Docker 和 Compose v2。" >&2; exit 1; }
compose=(docker compose --env-file "$DEPLOY_ENV_FILE" -f "$ROOT/compose.production.yml")
# Validate without printing secrets. Do not source config or export fallback secrets.
"${compose[@]}" config --quiet
case "$action" in
  check) echo "Compose 配置检查通过。" ;;
  up)
    # Build first so a build failure leaves existing containers running.
    "${compose[@]}" build
    "${compose[@]}" up -d --wait --wait-timeout 240 ;;
  apply) "${compose[@]}" up -d --no-build --wait --wait-timeout 240 ;;
  stop) shift; "${compose[@]}" stop "$@" ;;
  status) "${compose[@]}" ps ;;
  logs) shift; "${compose[@]}" logs --tail=100 -f "$@" ;;
esac
