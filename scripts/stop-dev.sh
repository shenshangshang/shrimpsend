#!/usr/bin/env bash
# 停止 start-dev.sh：宿主机 Web + Docker 服务端（MySQL / 悟空 IM / 后端）

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/docker-stack.sh
source "$ROOT/scripts/lib/docker-stack.sh"
PID_FILE="$ROOT/scripts/.dev-pids"

if [ -f "$PID_FILE" ]; then
  echo "停止本地 Web 进程..."
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
    fi
  done < "$PID_FILE"
  rm -f "$PID_FILE"
else
  echo "未找到 .dev-pids，没有由 start-dev.sh 启动的 Web 进程。"
fi

if command -v docker >/dev/null 2>&1; then
  (cd "$ROOT" && docker_stack_stop)
  echo "已停止 Docker 服务端（MySQL / 悟空 IM / 后端）。数据卷保留。"
fi

echo "已停止。"
echo "若仍有进程残留，可检查并结束占用 5200 / 9000 / 3000 端口的进程。"
