# Docker shared (docker-compose.yml tại repo root).
# make d-up / d-up-all chạy ensure-shared-network + ensure-gateway-sites trước compose up.

DC := docker compose --project-directory "$(ROOT)"

.PHONY: d-up d-down d-ps d-logs d-pull gateway-stop gateway-restart gw-stop gw-restart ensure-shared-network ensure-gateway-sites

# Folder gateway/sites phải thuộc user host — nếu compose up trước init-sites, Docker tạo root:root → Permission denied.
ensure-gateway-sites:
	@mkdir -p "$(ROOT)/gateway/sites"
	@if [ ! -w "$(ROOT)/gateway/sites" ]; then \
	  echo "[ERROR] $(ROOT)/gateway/sites not writable (thường do docker compose up trước init-sites)." >&2; \
	  echo "  Fix (sudo): sudo chown -R \$$(id -u):\$$(id -g) $(ROOT)/gateway/sites" >&2; \
	  echo "  Fix (docker): docker run --rm -v $(ROOT)/gateway/sites:/sites alpine chown -R \$$(id -u):\$$(id -g) /sites" >&2; \
	  exit 1; \
	fi

ensure-shared-network:
	@bash -c 'set -a; [ -f "$(ROOT)/.env" ] && . "$(ROOT)/.env"; set +a; \
	  net="$${BASE_SHARED_NETWORK_NAME:-base_shared_net}"; \
	  docker network inspect "$$net" >/dev/null 2>&1 || docker network create "$$net"'

# d-up: mạng external + gateway/sites → compose up (docker-compose.yml)
d-up: ensure-shared-network ensure-gateway-sites
	$(DC) up -d

d-down:
	$(DC) down

d-ps:
	$(DC) ps -a

d-logs:
	$(DC) logs -f

d-pull:
	$(DC) pull

gateway-stop:
	$(DC) stop gateway-nginx

gateway-restart:
	$(DC) restart gateway-nginx

gw-stop: gateway-stop
gw-restart: gateway-restart
