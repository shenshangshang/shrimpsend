#!/usr/bin/env bash
# Full Docker deployment on this machine, using an independent local config.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Keep this local entry point on the project VM even if the global context changes.
export DOCKER_CONTEXT="${LOCAL_DOCKER_CONTEXT:-colima-shrimpsend}"
export DEPLOY_ENV_FILE="${DEPLOY_ENV_FILE:-$ROOT/.env.local-deploy}"
# BuildKit fetches registry tokens on the host; follow the existing macOS proxy.
if command -v scutil >/dev/null 2>&1 && [ -z "${HTTPS_PROXY:-${https_proxy:-}}" ]; then
  proxy_settings="$(scutil --proxy)"
  proxy_enabled="$(printf '%s\n' "$proxy_settings" | awk '/HTTPSEnable :/ {print $3}')"
  proxy_host="$(printf '%s\n' "$proxy_settings" | awk '/HTTPSProxy :/ {print $3}')"
  proxy_port="$(printf '%s\n' "$proxy_settings" | awk '/HTTPSPort :/ {print $3}')"
  if [ "$proxy_enabled" = 1 ] && [ -n "$proxy_host" ] && [ -n "$proxy_port" ]; then
    export HTTPS_PROXY="http://$proxy_host:$proxy_port"
    export HTTP_PROXY="${HTTP_PROXY:-$HTTPS_PROXY}"
    export NO_PROXY="${NO_PROXY:-localhost,127.0.0.1,::1}"
  fi
fi
exec "$ROOT/scripts/deploy.sh" "$@"
