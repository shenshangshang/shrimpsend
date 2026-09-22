#!/usr/bin/env bash
# 启动本地开发环境：Docker 服务端（MySQL + 悟空 IM + 后端）+ 宿主机 Web
# 用法:
#   ./scripts/start-dev.sh              # 国内逻辑（默认 Spring profile）
#   ./scripts/start-dev.sh --overseas   # 海外 ShrimpSend 逻辑（dev-overseas）
#   ./scripts/start-dev.sh --rebuild    # 强制重建 backend 镜像
# 停止：./scripts/stop-dev.sh

if [ -z "${BASH_VERSION:-}" ]; then
  exec env bash "$0" "$@"
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/dev-common.sh
source "$ROOT/scripts/lib/dev-common.sh"
# shellcheck source=lib/docker-stack.sh
source "$ROOT/scripts/lib/docker-stack.sh"

cd "$ROOT"
PID_FILE="$ROOT/scripts/.dev-pids"
LOG_DIR="$ROOT/scripts/logs"
mkdir -p "$LOG_DIR"

WEB_LOG="$LOG_DIR/web.log"
STACK_LOG="$LOG_DIR/docker-stack.log"

OVERSEAS=false
for arg in "$@"; do
  case "$arg" in
    --overseas) OVERSEAS=true ;;
    --rebuild) echo "提示: start-dev 默认会重建 backend 镜像，--rebuild 可省略。" ;;
    *)
      die "未知参数: $arg（支持: --overseas --rebuild）"
      ;;
  esac
done

if [ -f "$ROOT/backend/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/backend/.env"
  set +a
elif [ -f "$ROOT/backend/.env.example" ]; then
  cp "$ROOT/backend/.env.example" "$ROOT/backend/.env"
  echo "已从 backend/.env.example 复制 backend/.env，请按需填写密钥。"
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/backend/.env"
  set +a
fi

if [ "$OVERSEAS" = true ] && [ -f "$ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

export REALTIME_BUS="${REALTIME_BUS:-wukongim}"
export WUKONGIM_MANAGER_TOKEN="${WUKONGIM_MANAGER_TOKEN:-dev-wukongim-manager-token}"
export WUKONGIM_WEBHOOK_HTTPADDR="http://backend:9000/api/wukongim/webhook"
export MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-changeme}"
export MYSQL_USER="${MYSQL_USER:-ultrasend}"
export MYSQL_PASSWORD="${MYSQL_PASSWORD:-changeme}"
# 容器连 Compose MySQL，不要沿用 backend/.env 里本机 JDBC 的 root 账号。
export SPRING_DATASOURCE_USERNAME="$MYSQL_USER"
export SPRING_DATASOURCE_PASSWORD="$MYSQL_PASSWORD"

if [ "$OVERSEAS" = true ]; then
  export SPRING_PROFILES_ACTIVE=dev-overseas
  export SPRING_DATASOURCE_URL="${SPRING_DATASOURCE_URL:-jdbc:mysql://mysql:3306/ultrasend_overseas?useUnicode=true&characterEncoding=utf8&useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true}"
  export WUKONGIM_WS_PUBLIC_URL="${WUKONGIM_WS_PUBLIC_URL:-ws://127.0.0.1:5200}"
else
  export SPRING_PROFILES_ACTIVE="${SPRING_PROFILES_ACTIVE:-}"
  export SPRING_DATASOURCE_URL="${SPRING_DATASOURCE_URL:-jdbc:mysql://mysql:3306/ultrasend?useUnicode=true&characterEncoding=utf8&useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true}"
  export WUKONGIM_WS_PUBLIC_URL="${WUKONGIM_WS_PUBLIC_URL:-ws://127.0.0.1:5200}"
fi

if [ -f "$PID_FILE" ]; then
  echo "发现已有 .dev-pids，先执行 stop-dev.sh"
  "$ROOT/scripts/stop-dev.sh" 2>/dev/null || true
  rm -f "$PID_FILE"
fi

if [ "$OVERSEAS" = true ]; then
  echo "模式: 海外本地 (Spring profile dev-overseas, DB ultrasend_overseas)"
else
  echo "模式: 国内本地 (默认 Spring profile, DB ultrasend)"
fi

echo "==> 启动前检查"
if ! command -v docker >/dev/null 2>&1; then
  die "需要 Docker 才能启动服务端（MySQL / 悟空 IM / 后端）。请安装 Docker 后重试。"
fi
if ! docker info >/dev/null 2>&1; then
  die "Docker 守护进程未运行。请先启动 Docker Desktop / dockerd。"
fi
if [ ! -x "$ROOT/web/node_modules/.bin/next" ]; then
  die "未找到 web 依赖（next）。请先执行: cd web && npm ci"
fi
chmod +x "$ROOT/docker/mysql/init-databases.sh" 2>/dev/null || true

echo "启动服务端 (docker compose --build: mysql + wukongim + backend)..."
: > "$STACK_LOG"
if ! docker_stack_up --build >> "$STACK_LOG" 2>&1; then
  fail_and_cleanup "Docker 服务端启动失败" "$STACK_LOG"
fi

if ! wait_http "悟空 IM" "http://127.0.0.1:5001/health" 60 "${WUKONGIM_MANAGER_TOKEN}"; then
  fail_and_cleanup "悟空 IM 未在 60 秒内就绪（docker compose logs wukongim）" "$STACK_LOG"
fi
if ! wait_http "后端 API" "http://127.0.0.1:9000/" 90; then
  docker compose logs --tail=40 backend >> "$STACK_LOG" 2>&1 || true
  fail_and_cleanup "后端未在 90 秒内就绪（请检查 docker compose logs backend）" "$STACK_LOG"
fi

echo "启动 Web (Next.js)..."
(cd "$ROOT/web" && exec npm run dev) >> "$WEB_LOG" 2>&1 &
pid_w=$!
echo "$pid_w" >> "$PID_FILE"

if ! wait_service "Web" "$pid_w" 20 "$WEB_LOG" port_3000; then
  reason="$(service_fail_reason "$pid_w" "端口 3000 在 20 秒内未就绪")"
  fail_and_cleanup "Web 启动失败：${reason}（若日志含 next: command not found，请执行 cd web && npm ci）" "$WEB_LOG"
fi

echo ""
echo "本地服务已启动："
echo "  MySQL:       127.0.0.1:3307  (docker, 容器内仍是 3306)"
echo "  悟空 IM API: http://127.0.0.1:5001  (docker, 仅本机)"
echo "  悟空 IM WS:  ws://localhost:5200"
echo "  后端 API:    http://localhost:9000  (docker)"
echo "  Web:         http://localhost:3000  (宿主机)"
echo ""
echo "日志: $LOG_DIR/ (docker-stack.log, web.log) · docker compose logs -f"
echo "停止: $ROOT/scripts/stop-dev.sh"
if [ "$OVERSEAS" = true ]; then
  echo ""
  echo "Stripe 本地 webhook（另开终端）:"
  echo "  stripe listen --forward-to localhost:9000/api/membership/stripe/webhook"
fi
