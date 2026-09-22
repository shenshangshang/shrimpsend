#!/usr/bin/env bash
# 仅启动海外逻辑服务端（Docker: MySQL + 悟空 IM + 后端），不启 Web。
# 全栈本地海外调试请用仓库根目录: ./scripts/start-dev.sh --overseas
#
# Stripe：backend/.env 或根 .env 中配置 STRIPE_*，另开终端:
#   stripe listen --forward-to localhost:9000/api/membership/stripe/webhook
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../lib/docker-stack.sh
source "$ROOT/scripts/lib/docker-stack.sh"
cd "$ROOT"

if [ -f "$ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi
if [ -f "$ROOT/backend/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/backend/.env"
  set +a
elif [ -f "$ROOT/backend/.env.example" ]; then
  cp "$ROOT/backend/.env.example" "$ROOT/backend/.env"
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/backend/.env"
  set +a
fi

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "[错误] 需要正在运行的 Docker" >&2
  exit 1
fi

export SPRING_PROFILES_ACTIVE=dev-overseas
export REALTIME_BUS="${REALTIME_BUS:-wukongim}"
export WUKONGIM_MANAGER_TOKEN="${WUKONGIM_MANAGER_TOKEN:-dev-wukongim-manager-token}"
export WUKONGIM_WEBHOOK_HTTPADDR="http://backend:9000/api/wukongim/webhook"
export WUKONGIM_WS_PUBLIC_URL="${WUKONGIM_WS_PUBLIC_URL:-ws://127.0.0.1:5200}"
export SPRING_DATASOURCE_URL="${SPRING_DATASOURCE_URL:-jdbc:mysql://mysql:3306/ultrasend_overseas?useUnicode=true&characterEncoding=utf8&useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true}"
export MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-changeme}"
export MYSQL_USER="${MYSQL_USER:-ultrasend}"
export MYSQL_PASSWORD="${MYSQL_PASSWORD:-changeme}"
export SPRING_DATASOURCE_USERNAME="$MYSQL_USER"
export SPRING_DATASOURCE_PASSWORD="$MYSQL_PASSWORD"

chmod +x "$ROOT/docker/mysql/init-databases.sh" 2>/dev/null || true
docker_stack_up --build
echo "海外服务端已启动。停止: docker compose stop mysql wukongim backend"
