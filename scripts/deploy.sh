#!/usr/bin/env bash
# 虾传 线上部署脚本（Docker 服务端 + 宿主机 Web）
# 用法:
#   ./scripts/deploy.sh          交互式部署（先选择国内/海外集群，再拉代码、构建、重启）
#   ./scripts/deploy.sh stop     仅停止服务
#   ./scripts/deploy.sh status   查看服务状态
#   ./scripts/deploy.sh logs     查看日志路径
#
# 集群选择：交互式部署时会在 git pull 之后立即询问「是否部署到海外集群 (ShrimpSend)」
#   - 选 N (默认): 走国内集群 xiachuan
#       后端 → application-prod.yml（打进 backend 镜像）
#       服务端 → docker compose: mysql + wukongim + backend
#   - 选 Y      : 走海外集群 ShrimpSend
#       后端 → application-prod-overseas.yml
#       悟空 IM → 同一 compose 服务（WUKONGIM_WS_PUBLIC_URL 指向海外域名）
#       Web 构建 → NEXT_PUBLIC_STRIPE_BILLING=live npm run build（与 .env 中 LIVE 价一致）
# 也可通过环境变量预先指定（适合 CI 等非交互场景）：
#   SPRING_PROFILE=prod-overseas CLUSTER_LABEL='海外 (ShrimpSend)' ./scripts/deploy.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/dev-common.sh
source "$ROOT/scripts/lib/dev-common.sh"
# shellcheck source=lib/ops-common.sh
source "$ROOT/scripts/lib/ops-common.sh"
# shellcheck source=lib/docker-stack.sh
source "$ROOT/scripts/lib/docker-stack.sh"
cd "$ROOT"

PID_FILE="$ROOT/scripts/.prod-pids"
LOG_DIR="$ROOT/scripts/logs"

# 默认走国内集群（xiachuan），可被交互式部署或环境变量覆盖
SPRING_PROFILE="${SPRING_PROFILE:-prod}"
CLUSTER_LABEL="${CLUSTER_LABEL:-国内 (xiachuan)}"

mkdir -p "$LOG_DIR"

# 从 ops 仓同步生产配置到业务仓（gitignored 的 prod 文件）
sync_ops_config() {
  local sync_script="$ROOT/scripts/sync-to-build-machine.sh"
  local ops_dir
  ops_dir="$(resolve_ultrasend_ops_dir "$ROOT")"
  if [ ! -x "$sync_script" ]; then
    chmod +x "$sync_script" 2>/dev/null || true
  fi
  if [ -f "$sync_script" ]; then
    echo "  -> 同步 ops 配置 (ULTRASEND_OPS_DIR=$ops_dir)..."
    ULTRASEND_OPS_DIR="$ops_dir" "$sync_script"
  else
    echo "  [警告] 未找到 $sync_script，跳过 ops 同步"
  fi
}

assert_prod_config_present() {
  if [ "$SPRING_PROFILE" = "prod-overseas" ]; then
    if [ ! -f "$ROOT/backend/src/main/resources/application-prod-overseas.yml" ]; then
      echo "  [错误] 缺少 application-prod-overseas.yml"
      echo "  请 clone ops 到 ../ops 或设置 ULTRASEND_OPS_DIR，并运行 scripts/sync-to-build-machine.sh"
      exit 1
    fi
  else
    if [ ! -f "$ROOT/backend/src/main/resources/application-prod.yml" ]; then
      echo "  [错误] 缺少 application-prod.yml"
      echo "  请 clone ops 到 ../ops 或设置 ULTRASEND_OPS_DIR，并运行 scripts/sync-to-build-machine.sh"
      exit 1
    fi
  fi
}

# ── 辅助函数 ──

confirm() {
  local prompt="$1" default="${2:-N}"
  if [ "$default" = "Y" ]; then
    prompt="$prompt (Y/n): "
  else
    prompt="$prompt (y/N): "
  fi
  read -r -p "$prompt" answer
  answer="${answer:-$default}"
  case "$answer" in
    [yY]) return 0 ;;
    *) return 1 ;;
  esac
}

rotate_log() {
  local file="$1"
  if [ -f "$file" ] && [ -s "$file" ]; then
    mv "$file" "${file}.$(date +%Y%m%d_%H%M%S)"
  fi
}

web_standalone_app_dir() {
  if [ -f "$ROOT/web/.next/standalone/web/server.js" ]; then
    echo "$ROOT/web/.next/standalone/web"
  else
    echo "$ROOT/web/.next/standalone"
  fi
}

web_standalone_server() {
  local app_dir
  app_dir="$(web_standalone_app_dir)"
  echo "$app_dir/server.js"
}

stop_services() {
  # 先杀 PID 文件中记录的进程（Web）
  if [ -f "$PID_FILE" ]; then
    while read -r pid; do
      [ -z "$pid" ] && continue
      if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        echo "  已发 SIGTERM: PID $pid"
      fi
    done < "$PID_FILE"
    sleep 2
    while read -r pid; do
      [ -z "$pid" ] && continue
      if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
        echo "  已强制终止: PID $pid"
      fi
    done < "$PID_FILE"
    rm -f "$PID_FILE"
  fi

  local pids
  pids=$(lsof -ti :3000 2>/dev/null || true)
  if [ -n "$pids" ]; then
    echo "  端口 3000 (Web) 仍被占用，清理 PID: $pids"
    echo "$pids" | xargs kill -9 2>/dev/null || true
  fi
  fuser -k 3000/tcp 2>/dev/null || true

  if command -v docker >/dev/null 2>&1; then
    (cd "$ROOT" && docker_stack_stop)
  fi
  sleep 2
  echo "  已停止所有服务"
}

show_status() {
  echo "服务状态:"
  if command -v docker >/dev/null 2>&1; then
    docker_stack_ps || true
  fi
  if [ -f "$PID_FILE" ]; then
    while read -r pid; do
      [ -z "$pid" ] && continue
      if kill -0 "$pid" 2>/dev/null; then
        echo "  Web: 运行中 (PID $pid)"
      else
        echo "  Web: 已停止 (PID $pid 不存在)"
      fi
    done < "$PID_FILE"
  else
    echo "  Web: 未记录 PID"
  fi
}

start_services() {
  echo ""
  echo "启动服务..."

  rotate_log "$LOG_DIR/docker-stack.log"
  rotate_log "$LOG_DIR/web.log"

  if ! command -v docker >/dev/null 2>&1; then
    echo "  [错误] 需要 Docker 才能运行服务端（MySQL / 悟空 IM / 后端）"
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "  [错误] Docker 守护进程未运行"
    exit 1
  fi

  export SPRING_PROFILES_ACTIVE="$SPRING_PROFILE"
  export REALTIME_BUS="${REALTIME_BUS:-wukongim}"
  export WUKONGIM_MANAGER_TOKEN="${WUKONGIM_MANAGER_TOKEN:-dev-wukongim-manager-token}"
  export WUKONGIM_WEBHOOK_HTTPADDR="${WUKONGIM_WEBHOOK_HTTPADDR:-http://backend:9000/api/wukongim/webhook}"
  export MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-changeme}"
  export MYSQL_USER="${MYSQL_USER:-ultrasend}"
  export MYSQL_PASSWORD="${MYSQL_PASSWORD:-changeme}"
  export SPRING_DATASOURCE_USERNAME="${SPRING_DATASOURCE_USERNAME:-$MYSQL_USER}"
  export SPRING_DATASOURCE_PASSWORD="${SPRING_DATASOURCE_PASSWORD:-$MYSQL_PASSWORD}"
  if [ "$SPRING_PROFILE" = "prod-overseas" ]; then
    export WUKONGIM_WS_PUBLIC_URL="${WUKONGIM_WS_PUBLIC_URL:-wss://api.shrimpsend.com/wkws}"
    export SPRING_DATASOURCE_URL="${SPRING_DATASOURCE_URL:-jdbc:mysql://mysql:3306/ultrasend_overseas?useUnicode=true&characterEncoding=utf8&useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true}"
  else
    export WUKONGIM_WS_PUBLIC_URL="${WUKONGIM_WS_PUBLIC_URL:-wss://api.xiachuan.net/wkws}"
    export SPRING_DATASOURCE_URL="${SPRING_DATASOURCE_URL:-jdbc:mysql://mysql:3306/ultrasend?useUnicode=true&characterEncoding=utf8&useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true}"
  fi
  if [ ! -f "$ROOT/backend/.env" ]; then
    touch "$ROOT/backend/.env"
  fi
  chmod +x "$ROOT/docker/mysql/init-databases.sh" 2>/dev/null || true

  echo "  启动 Docker 服务端 (mysql + wukongim + backend)  profile=$SPRING_PROFILE"
  docker_stack_up --build >> "$LOG_DIR/docker-stack.log" 2>&1
  printf "  等待悟空 IM 就绪"
  local wk_ready=0
  for i in $(seq 1 60); do
    if curl -sf -H "token: ${WUKONGIM_MANAGER_TOKEN}" http://127.0.0.1:5001/health >/dev/null 2>&1; then
      wk_ready=1
      break
    fi
    printf "."
    sleep 1
  done
  if [ $wk_ready -eq 1 ]; then
    echo " OK (5200 / 127.0.0.1:5001)"
  else
    echo " 失败！中止部署。"
    docker compose logs --tail=20 wukongim 2>/dev/null | sed 's/^/    /' || true
    exit 1
  fi

  printf "  等待后端就绪"
  local ready=0
  for i in $(seq 1 90); do
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:9000/ 2>/dev/null | grep -q '200'; then
      ready=1
      break
    fi
    printf "."
    sleep 1
  done
  if [ $ready -eq 1 ]; then
    echo " OK (端口 9000)"
  else
    echo " 失败！中止部署。"
    docker compose logs --tail=30 backend 2>/dev/null | sed 's/^/    /' || true
    exit 1
  fi

  # Web (standalone 模式：用 node 直接启动)
  local web_server
  web_server="$(web_standalone_server)"
  if [ ! -f "$web_server" ]; then
    echo "  [错误] $web_server 不存在！"
    echo "  请先构建 Web（选择 [3/3] 重新构建）"
    echo ""
    echo "  部署未完成：Web 未启动"
    return 1
  fi

  HOSTNAME=0.0.0.0 PORT=3000 node "$web_server" >> "$LOG_DIR/web.log" 2>&1 &
  local pid_w=$!
  echo $pid_w >> "$PID_FILE"

  printf "  等待 Web 就绪"
  local web_ready=0
  for i in $(seq 1 20); do
    sleep 1
    if ! kill -0 "$pid_w" 2>/dev/null; then
      break
    fi
    if curl -s -o /dev/null http://localhost:3000 2>/dev/null; then
      web_ready=1
      break
    fi
    printf "."
  done
  if [ $web_ready -eq 1 ]; then
    echo " OK (PID $pid_w, 端口 3000)"
  else
    echo ""
    echo "  [错误] Web 启动失败！"
    if ! kill -0 "$pid_w" 2>/dev/null; then
      echo "  进程已退出（PID $pid_w 不存在）"
    else
      echo "  进程存在但端口 3000 未就绪（PID $pid_w）"
    fi
    echo "  完整日志: $LOG_DIR/web.log"
    echo "  最后 15 行:"
    tail -15 "$LOG_DIR/web.log" 2>/dev/null | sed 's/^/    /'
  fi
}

# ── 子命令处理 ──

case "${1:-}" in
  stop)
    echo "停止服务..."
    stop_services
    exit 0
    ;;
  status)
    show_status
    exit 0
    ;;
  logs)
    echo "日志目录: $LOG_DIR/"
    ls -lht "$LOG_DIR/" 2>/dev/null || echo "  暂无日志"
    echo ""
    echo "Docker 服务端日志: docker compose logs -f mysql wukongim backend"
    exit 0
    ;;
  help|--help|-h)
    echo "用法:"
    echo "  ./scripts/deploy.sh          交互式部署（先询问国内/海外集群）"
    echo "  ./scripts/deploy.sh stop     停止服务"
    echo "  ./scripts/deploy.sh status   查看服务状态"
    echo "  ./scripts/deploy.sh logs     查看日志文件"
    echo ""
    echo "环境变量（非交互式）:"
    echo "  SPRING_PROFILE=prod              使用 application-prod.yml (默认)"
    echo "  SPRING_PROFILE=prod-overseas     使用 application-prod-overseas.yml"
    echo ""
    echo "环境变量:"
    echo "  ULTRASEND_OPS_DIR                ops 仓路径（未设置时自动查找 ../ops）"
    echo ""
    echo "海外 Web 构建: 选海外集群且构建 Web 时设置 NEXT_PUBLIC_STRIPE_BILLING=live（使用 web/.env.local 中 LIVE 价）。"
    exit 0
    ;;
esac

# ── 交互式部署主流程 ──

echo ""
echo "=========================================="
echo "       虾传 线上部署"
echo "=========================================="
echo ""

# [1/4] 拉代码（先拉到最新，再让用户选环境，避免拿旧脚本部署）
if confirm "[1/4] 是否拉取最新代码 (git pull)?"; then
  echo "  -> git pull ..."
  git pull
  echo "  -> 完成"
else
  echo "  -> 跳过"
fi
echo ""

# [2/4] 选择部署集群（国内 / 海外）—— 拉完代码立刻选，决定后续构建/启动用的 profile
if confirm "[2/4] 是否部署到海外集群 (ShrimpSend)?"; then
  SPRING_PROFILE="prod-overseas"
  CLUSTER_LABEL="海外 (ShrimpSend)"
  echo "  -> 已选择: $CLUSTER_LABEL  (Spring profile: $SPRING_PROFILE)"
else
  SPRING_PROFILE="prod"
  CLUSTER_LABEL="国内 (xiachuan)"
  echo "  -> 已选择: $CLUSTER_LABEL  (Spring profile: $SPRING_PROFILE)"
fi
echo ""

# 从 ops 同步生产配置（application-prod*.yml 等）
if confirm "是否从 ops 仓同步生产配置?"; then
  sync_ops_config
else
  echo "  -> 跳过 ops 同步（使用业务仓内已有 prod 文件）"
fi
assert_prod_config_present
echo ""

# [3/4] 构建后端 Docker 镜像
if confirm "[3/4] 是否现在构建后端 Docker 镜像 (docker compose build backend)?"; then
  echo "  -> 构建中（首次可能需要几分钟）..."
  if [ ! -f "$ROOT/backend/.env" ]; then
    touch "$ROOT/backend/.env"
  fi
  docker compose build backend
  echo "  -> 构建完成"
else
  echo "  -> 跳过（启动时仍会 docker compose up --build）"
fi
echo ""

# [4/4] 构建 Web
if confirm "[4/4] 是否重新构建 Web (npm run build)?"; then
  echo "  -> 清理旧构建..."
  rm -rf "$ROOT/web/.next"
  echo "  -> 安装依赖..."
  (cd "$ROOT/web" && npm ci)
  echo "  -> 构建中..."
  if [ "$SPRING_PROFILE" = "prod-overseas" ]; then
    echo "  -> 海外 Web: NEXT_PUBLIC_STRIPE_BILLING=live（Stripe 线上价，见 web/.env.local）"
    (cd "$ROOT/web" && APP_PUBLIC_WEB_BASE_URL="${APP_PUBLIC_WEB_BASE_URL:-https://shrimpsend.com}" NEXT_PUBLIC_WEB_BASE_URL="${NEXT_PUBLIC_WEB_BASE_URL:-https://shrimpsend.com}" NEXT_PUBLIC_STRIPE_BILLING=live npm run build)
  else
    (cd "$ROOT/web" && APP_PUBLIC_WEB_BASE_URL="${APP_PUBLIC_WEB_BASE_URL:-https://xiachuan.net}" NEXT_PUBLIC_WEB_BASE_URL="${NEXT_PUBLIC_WEB_BASE_URL:-https://xiachuan.net}" npm run build)
  fi
  echo "  -> 拷贝静态资源到 standalone..."
  web_app_dir="$(web_standalone_app_dir)"
  mkdir -p "$web_app_dir/.next"
  rm -rf "$web_app_dir/.next/static" "$web_app_dir/public"
  cp -R "$ROOT/web/.next/static" "$web_app_dir/.next/static"
  cp -R "$ROOT/web/public" "$web_app_dir/public"
  echo "  -> 构建完成"
else
  echo "  -> 跳过"
  if [ ! -f "$(web_standalone_server)" ]; then
    echo "  [警告] 未发现 $(web_standalone_server)，Web 将无法启动！"
  fi
fi
echo ""

# 停止旧服务
echo "停止旧服务..."
stop_services
echo ""

# 启动全部
start_services

echo ""
echo "=========================================="
echo "            部署完成"
echo "=========================================="
echo "  集群        : $CLUSTER_LABEL  (profile: $SPRING_PROFILE)"
echo "  MySQL      : 127.0.0.1:3306  (docker)"
echo "  悟空 IM    : 5200   健康检查: http://127.0.0.1:5001/health"
echo "  后端 API   : 9000   docker compose logs -f backend"
echo "  Web        : 3000   日志: $LOG_DIR/web.log"
echo ""
echo "  停止服务: ./scripts/deploy.sh stop"
echo "  查看状态: ./scripts/deploy.sh status"
echo "  查看日志: ./scripts/deploy.sh logs"
echo "=========================================="
