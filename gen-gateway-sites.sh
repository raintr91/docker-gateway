#!/usr/bin/env bash
# Sinh nginx gateway từ routes.json (không giới hạn số host / portal mỗi dự án).
# .env: INTERNAL_API_HOST, API_CONTAINER_PORT, PORTAL_CONTAINER_PORT.
#
# Usage: bash gen-gateway-sites.sh [path/to/.env] [path/to/sites-dir]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
ENV_FILE="${1:-$PROJECT_ROOT/.env}"
SITES_DIR="${2:-$PROJECT_ROOT/gateway/sites}"

# shellcheck source=lib/routes-json.sh
source "$SCRIPT_DIR/lib/routes-json.sh"
routes_json_init "$SCRIPT_DIR" || exit 1

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[ERROR] Missing env file: $ENV_FILE (cp .env.example .env)" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

INTERNAL_DEFAULT="${INTERNAL_API_HOST:-laravel.api.com}"
API_CONTAINER_PORT="${API_CONTAINER_PORT:-80}"
PORTAL_CONTAINER_PORT="${PORTAL_CONTAINER_PORT:-3000}"
EXTERNAL_NODE_CONTAINER="${EXTERNAL_NODE_CONTAINER:-${PROJECT_NAME:-local_dev}_external_frontend_node}"
EXTERNAL_GATEWAY_PROXY="${EXTERNAL_GATEWAY_PROXY:-container}"
EXTERNAL_NGINX_CONTAINER="${EXTERNAL_NGINX_CONTAINER:-${PROJECT_NAME:-local_dev}_external_nginx}"
EXTERNAL_PHP82_PORT="${EXTERNAL_PHP82_PORT:-18081}"
EXTERNAL_PHP83_PORT="${EXTERNAL_PHP83_PORT:-18082}"
EXTERNAL_PHP82_SCENARIO_PORT="${EXTERNAL_PHP82_SCENARIO_PORT:-18084}"
GATEWAY_CONTAINER="${GATEWAY_CONTAINER:-${PROJECT_NAME:-local_dev}_gateway_nginx}"

domain_to_conf() {
  printf '%s' "$1" | sed 's/[^a-zA-Z0-9._-]/_/g'
}

mkdir -p "$SITES_DIR"

# Infra (phpmyadmin, pgadmin, redisadmin, mail, mock, stackport) — không sinh từ routes.json.
# Copy template từ gateway/sites.example/ nếu file chưa có (không ghi đè chỉnh tay).
SITES_EXAMPLE_DIR="$PROJECT_ROOT/gateway/sites.example"
copy_sites_example() {
  [[ -d "$SITES_EXAMPLE_DIR" ]] || return 0
  local f base
  for f in "$SITES_EXAMPLE_DIR"/*.conf; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    if [[ ! -f "$SITES_DIR/$base" ]]; then
      cp "$f" "$SITES_DIR/$base"
      echo "[INFO] Copied infra template $base (from sites.example)"
    fi
  done
}
copy_sites_example

write_api_conf() {
  local api_dom=$1 stack_slug=$2 internal_h=$3
  local api_upstream api_note
  api_upstream="http://${stack_slug}-api-nginx:${API_CONTAINER_PORT}"
  api_note="${stack_slug}-api-nginx:${API_CONTAINER_PORT} (Docker network)"
  local f="$SITES_DIR/$(domain_to_conf "$api_dom").conf"
  local existed=0
  [[ -f "$f" ]] && existed=1
  cat >"$f" <<EOF
# API ${api_dom} → ${api_note} (proxy Host: ${internal_h})
server {
    listen 80;
    server_name ${api_dom};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name ${api_dom};
    ssl_certificate /etc/nginx/certs/dev-server.fullchain.crt;
    ssl_certificate_key /etc/nginx/certs/dev-server.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    resolver 127.0.0.11 valid=10s ipv6=off;

    # PHPUnit HTML report — relative redirect keeps the browser on saas-api.local.com.
    location = /coverage/ {
        return 301 /coverage;
    }

    location = /coverage {
        set \$api_upstream ${api_upstream};
        proxy_http_version 1.1;
        proxy_pass \$api_upstream;
        proxy_set_header Host ${internal_h};
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
        proxy_pass_header Set-Cookie;
        proxy_pass_header Vary;
    }

    location ^~ /coverage/ {
        set \$api_upstream ${api_upstream};
        proxy_http_version 1.1;
        proxy_pass \$api_upstream;
        proxy_set_header Host ${internal_h};
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
        proxy_pass_header Set-Cookie;
        proxy_pass_header Vary;
    }

    location / {
        set \$api_upstream ${api_upstream};
        proxy_http_version 1.1;
        proxy_pass \$api_upstream;
        proxy_set_header Host ${internal_h};
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
        proxy_pass_header Set-Cookie;
        proxy_pass_header Vary;
    }
}
EOF
  if [[ "$existed" -eq 1 ]]; then
    echo "[INFO] Overwrote $f"
  else
    echo "[INFO] Created $f"
  fi
}

write_portal_conf() {
  local portal_dom=$1 stack_slug=$2
  local portal_port=$PORTAL_CONTAINER_PORT
  local f="$SITES_DIR/$(domain_to_conf "$portal_dom").conf"
  local existed=0
  local portal_target="http://${stack_slug}-portal-node:${portal_port}"
  local portal_note="${stack_slug}-portal-node:${portal_port} (Docker network)"
  [[ -f "$f" ]] && existed=1
  cat >"$f" <<EOF
# Portal ${portal_dom} → ${portal_note}
server {
    listen 80;
    server_name ${portal_dom};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name ${portal_dom};
    ssl_certificate /etc/nginx/certs/dev-server.fullchain.crt;
    ssl_certificate_key /etc/nginx/certs/dev-server.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    resolver 127.0.0.11 valid=10s ipv6=off;
    location / {
        set \$portal_upstream ${portal_target};
        proxy_pass \$portal_upstream;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF
  if [[ "$existed" -eq 1 ]]; then
    echo "[INFO] Overwrote $f"
  else
    echo "[INFO] Created $f"
  fi
}

# Map host-published port (routes.json) → external-nginx listen port inside Docker.
external_nginx_listen_port() {
  case "$1" in
    "$EXTERNAL_PHP82_PORT") echo 8081 ;;
    "$EXTERNAL_PHP83_PORT") echo 8082 ;;
    "$EXTERNAL_PHP82_SCENARIO_PORT") echo 8084 ;;
    *) echo "" ;;
  esac
}

resolve_external_web_upstream() {
  local web_port=$1
  local listen
  listen="$(external_nginx_listen_port "$web_port")"
  if [[ "$EXTERNAL_GATEWAY_PROXY" == "container" && -n "$listen" ]]; then
    echo "http://${EXTERNAL_NGINX_CONTAINER}:${listen}"
    return
  fi
  echo "http://host.docker.internal:${web_port}"
}

write_web_conf() {
  local web_dom=$1 web_port=$2 proxy_host=$3
  local web_upstream
  web_upstream="$(resolve_external_web_upstream "$web_port")"
  local f="$SITES_DIR/$(domain_to_conf "$web_dom").conf"
  local existed=0
  [[ -f "$f" ]] && existed=1
  cat >"$f" <<EOF
# Web ${web_dom} → ${web_upstream} (proxy Host: ${proxy_host}; EXTERNAL_GATEWAY_PROXY=${EXTERNAL_GATEWAY_PROXY})
server {
    listen 80;
    server_name ${web_dom};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name ${web_dom};
    ssl_certificate /etc/nginx/certs/dev-server.fullchain.crt;
    ssl_certificate_key /etc/nginx/certs/dev-server.key;
    ssl_protocols TLSv1.2 TLSv1.3;
  resolver 127.0.0.11 valid=10s ipv6=off;
    location / {
    set \$web_upstream ${web_upstream};
        proxy_http_version 1.1;
    proxy_pass \$web_upstream;
        proxy_set_header Host ${proxy_host};
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass_header Set-Cookie;
        proxy_pass_header Vary;
    }
}
EOF
  if [[ "$existed" -eq 1 ]]; then
    echo "[INFO] Overwrote $f"
  else
    echo "[INFO] Created $f"
  fi
}

write_external_node_conf() {
  local node_dom=$1 node_port=$2
  local f="$SITES_DIR/$(domain_to_conf "$node_dom").conf"
  local existed=0
  local node_target="http://${EXTERNAL_NODE_CONTAINER}:${node_port}"
  local node_note="${EXTERNAL_NODE_CONTAINER}:${node_port} (Docker network)"
  [[ -f "$f" ]] && existed=1
  cat >"$f" <<EOF
# External Nuxt ${node_dom} → ${node_note}
server {
    listen 80;
    server_name ${node_dom};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name ${node_dom};
    ssl_certificate /etc/nginx/certs/dev-server.fullchain.crt;
    ssl_certificate_key /etc/nginx/certs/dev-server.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    resolver 127.0.0.11 valid=10s ipv6=off;
    location / {
        set \$node_upstream ${node_target};
        proxy_pass \$node_upstream;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF
  if [[ "$existed" -eq 1 ]]; then
    echo "[INFO] Overwrote $f"
  else
    echo "[INFO] Created $f"
  fi
}

used=0
while IFS=$'\t' read -r proj role host port stack_slug internal_h || [[ -n "${proj:-}" ]]; do
  [[ -z "${proj:-}" ]] && continue
  [[ "$port" == "-" ]] && port=""
  [[ "$stack_slug" == "-" ]] && stack_slug=""
  [[ "$internal_h" == "-" ]] && internal_h=""
  case "$role" in
    api)
      [[ -z "$stack_slug" ]] && stack_slug="$proj"
      internal_h="${internal_h:-$INTERNAL_DEFAULT}"
      write_api_conf "$host" "$stack_slug" "$internal_h"
      ((used++)) || true
      ;;
    portal)
      [[ -z "$stack_slug" ]] && stack_slug="$proj"
      write_portal_conf "$host" "$stack_slug"
      ((used++)) || true
      ;;
    web)
      write_web_conf "$host" "$port" "$host"
      ((used++)) || true
      ;;
    node)
      write_external_node_conf "$host" "$port"
      ((used++)) || true
      ;;
    *)
      echo "[ERROR] Unknown route role: $role (project $proj)" >&2
      exit 1
      ;;
  esac
done < <(routes_json_records)

if [[ "$used" -eq 0 ]]; then
  echo "[ERROR] No routes in $ROUTES_JSON — thêm ít nhất một project" >&2
  exit 1
fi

echo "[DONE] Gateway sites in: $SITES_DIR/ (from $ROUTES_JSON)"

bash "$SCRIPT_DIR/gen-gateway-network-aliases.sh" "$ENV_FILE"

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$GATEWAY_CONTAINER"; then
  if docker exec "$GATEWAY_CONTAINER" nginx -t >/dev/null 2>&1; then
    docker exec "$GATEWAY_CONTAINER" nginx -s reload
    echo "[INFO] Reloaded gateway nginx ($GATEWAY_CONTAINER)"
  else
    echo "[WARN] Gateway config test failed — reload skipped" >&2
  fi
else
  echo "[INFO] Gateway not running ($GATEWAY_CONTAINER) — start stack then: docker exec $GATEWAY_CONTAINER nginx -s reload"
fi
