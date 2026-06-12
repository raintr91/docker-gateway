# docker-compose.services.yml (LocalStack, Mailpit, mock hub, StackPort, MySQL 8.0).
# Được include từ Makefile — biến $(ROOT) do Makefile gốc định nghĩa trước.

DCS := docker compose --project-directory "$(ROOT)" -f docker-compose.yml -f docker-compose.services.yml

.PHONY: d-services-up d-services-down d-services-ps d-services-logs d-up-all d-down-all \
	mysql80-up mysql80-down mysql80-restart mysql80-ps mysql80-logs

d-services-up:
	$(DCS) up -d redis localstack mailpit mock-api stackport

d-services-down:
	$(DCS) stop redis localstack mailpit mock-api stackport

d-services-ps:
	$(DCS) ps -a

d-services-logs:
	$(DCS) logs -f

d-up-all:
	$(DCS) up -d --remove-orphans

d-down-all:
	$(DCS) down --remove-orphans

mysql80-up:
	$(DCS) up -d mysql-80

mysql80-down:
	$(DCS) stop mysql-80

mysql80-restart:
	$(DCS) restart mysql-80

mysql80-ps:
	$(DCS) ps mysql-80

mysql80-logs:
	$(DCS) logs -f mysql-80
