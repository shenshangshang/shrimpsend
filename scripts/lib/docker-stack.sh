#!/usr/bin/env bash
# Docker Compose helpers for the server stack (MySQL + WuKongIM + backend).
# Sourced by start-dev.sh and deploy.sh.

SERVER_SERVICES=(mysql wukongim backend)

docker_stack_ensure_backend_env() {
  local root="${ROOT:-.}"
  if [ -f "$root/backend/.env" ]; then
    return 0
  fi
  if [ -f "$root/backend/.env.example" ]; then
    cp "$root/backend/.env.example" "$root/backend/.env"
    echo "已从 backend/.env.example 复制 backend/.env（compose env_file 需要该文件）"
  else
    touch "$root/backend/.env"
  fi
}

# Init scripts only run on first MySQL volume. Re-apply grants for existing volumes.
docker_stack_ensure_databases() {
  local pass="${MYSQL_ROOT_PASSWORD:-changeme}"
  local user="${MYSQL_USER:-ultrasend}"
  local i
  for i in $(seq 1 40); do
    if docker compose exec -T mysql mysqladmin ping -h localhost -uroot -p"${pass}" --silent >/dev/null 2>&1; then
      docker compose exec -T mysql mysql -uroot -p"${pass}" -e "
        CREATE DATABASE IF NOT EXISTS ultrasend CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        CREATE DATABASE IF NOT EXISTS ultrasend_overseas CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        CREATE USER IF NOT EXISTS '${user}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD:-changeme}';
        GRANT ALL PRIVILEGES ON ultrasend.* TO '${user}'@'%';
        GRANT ALL PRIVILEGES ON ultrasend_overseas.* TO '${user}'@'%';
        FLUSH PRIVILEGES;
      " >/dev/null 2>&1 || true
      return 0
    fi
    sleep 1
  done
  echo "警告: MySQL 未在超时内就绪，跳过补建库（首次数据卷会由 init-databases.sh 建库）" >&2
}

docker_stack_up() {
  local build_flag=()
  local services=("${SERVER_SERVICES[@]}")
  if [ "${1:-}" = "--build" ]; then
    build_flag=(--build)
    shift
  fi
  if [ "$#" -gt 0 ]; then
    services=("$@")
  fi
  docker_stack_ensure_backend_env
  chmod +x "${ROOT:-.}/docker/mysql/init-databases.sh" 2>/dev/null || true
  if ! docker compose up -d "${build_flag[@]}" "${services[@]}"; then
    echo "阿里云悟空镜像失败，改用 Docker Hub wukongim/wukongim:v2"
    WUKONGIM_IMAGE=wukongim/wukongim:v2 docker compose up -d "${build_flag[@]}" "${services[@]}"
  fi
  docker_stack_ensure_databases
}

docker_stack_stop() {
  docker compose stop mysql wukongim backend >/dev/null 2>&1 || true
}

docker_stack_ps() {
  docker compose ps mysql wukongim backend
}
