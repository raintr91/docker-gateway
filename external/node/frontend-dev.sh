#!/usr/bin/env sh
set -eu

PORT="${EXTERNAL_NODE_PORT:-3001}"
export HOME="${HOME:-/tmp}"
mkdir -p /tmp/cache /tmp/config
export npm_config_cache=/tmp/npm-cache
mkdir -p "$npm_config_cache"
export XDG_CACHE_HOME=/tmp/cache
export XDG_CONFIG_HOME=/tmp/config

cd /workspace/mairy-frontend

# Stale Nitro dev sockets after container restart cause EADDRINUSE and hung :3001 (gateway 504).
rm -rf /tmp/nitro 2>/dev/null || true

if [ ! -x node_modules/.bin/nuxt ]; then
  if [ -f package-lock.json ]; then
    npm ci
  else
    npm install
  fi
fi

exec npm run dev -- --host 0.0.0.0 --port "$PORT"
