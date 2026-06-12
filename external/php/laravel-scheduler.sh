#!/bin/sh
set -eu

APP_DIR="${LARAVEL_SCHEDULER_APP_DIR:-/var/www/mairy-backend}"
cd "$APP_DIR"

echo "[scheduler] Laravel schedule loop — ${APP_DIR} (every 60s)"

while true; do
  php artisan schedule:run --no-interaction 2>&1 || true
  sleep 60
done
