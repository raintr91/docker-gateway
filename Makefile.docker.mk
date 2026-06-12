# Docker shared (docker-compose.yml tại repo root).
# Được include từ Makefile — biến $(ROOT) do Makefile gốc định nghĩa trước.

DC := docker compose --project-directory "$(ROOT)"

.PHONY: d-up d-down d-ps d-logs d-pull gateway-stop gateway-restart gw-stop gw-restart

d-up:
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
