#!/usr/bin/env sh
# Root: chown node_modules → setpriv → chạy npm/nuxt (không dùng corepack).
set -eu

UID_NUM="${HOST_UID:-1000}"
GID_NUM="${HOST_GID:-1000}"
NM_DIR="/workspace/mairy-frontend/node_modules"

if [ "$(id -u)" = "0" ]; then
  if [ -d "$NM_DIR" ]; then
    cur="$(stat -c '%u:%g' "$NM_DIR" 2>/dev/null || echo 0:0)"
    if [ "$cur" != "${UID_NUM}:${GID_NUM}" ]; then
      chown -R "${UID_NUM}:${GID_NUM}" "$NM_DIR"
    fi
  fi
  exec setpriv --reuid="${UID_NUM}" --regid="${GID_NUM}" --init-groups -- "$@"
fi

exec "$@"
