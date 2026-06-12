# Dừng / gỡ toàn bộ stack dev (proj + external + shared + services).
# stop-all: chỉ stop container. down-all: compose down (xóa container, giữ volume).

.PHONY: stop-all down-all docker-stop-all

stop-all:
	@echo "[stop-all] Shared + services..."
	-docker compose --project-directory "$(ROOT)" -f docker-compose.yml -f docker-compose.services.yml stop
	@echo "[DONE] stop-all"

down-all:
	@echo "[down-all] Shared + services..."
	-docker compose --project-directory "$(ROOT)" -f docker-compose.yml -f docker-compose.services.yml down --remove-orphans
	@echo "[DONE] down-all"

docker-stop-all:
	@echo "[docker-stop-all] Stopping all running Docker containers on this machine..."
	@ids="$$(docker ps -q)"; \
	if [ -n "$$ids" ]; then \
		docker stop $$ids; \
		echo "[DONE] docker-stop-all"; \
	else \
		echo "[docker-stop-all] No running containers"; \
	fi
