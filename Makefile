# Makefile gốc repo — `make help`
# Chi tiết: Makefile.docker.mk, Makefile.function.mk, Makefile.services.mk, Makefile.exec.mk, Makefile.all.mk

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
MAKEFLAGS += --no-print-directory

include Makefile.docker.mk
include Makefile.function.mk
include Makefile.services.mk
include Makefile.exec.mk
include Makefile.all.mk

.PHONY: help
.DEFAULT_GOAL := help

help:
	@echo "Repo: $(ROOT)"
	@echo ""
	@echo "Docker shared (Makefile.docker.mk):"
	@echo "  make d-up | d-down | d-ps | d-logs | d-pull"
	@echo "  make gateway-stop | gateway-restart  (alias: gw-stop | gw-restart)"
	@echo ""
	@echo "Script tiện ích (Makefile.function.mk):"
	@echo "  make gen-sites | gw    — sites.example (infra) + routes.json (project)"
	@echo "  make init-sites        — chỉ copy sites.example → gateway/sites"
	@echo "  make gw-safe           — gen-sites + up gateway + nginx -t"
	@echo "  make hosts             — print-hosts-from-env.sh (WSL + Windows)"
	@echo "  make gen-ssl | ssl     — gen-dev-ssl.sh + combined CA"
	@echo "  make certs-combined    — refresh certs/combined-ca.pem only"
	@echo ""
	@echo "Dev services (Makefile.services.mk):"
	@echo "  make d-services-up | d-services-down | d-services-ps | d-services-logs"
	@echo "  make d-up-all | d-down-all"
	@echo "  make mysql80-up | mysql80-down | mysql80-restart | mysql80-ps | mysql80-logs"
	@echo ""
	@echo "Exec shell (Makefile.exec.mk):"
	@echo "  make exec SVC=<alias> [CMD='...']  |  make exec <alias>  |  make exec-list"
	@echo "  vd. make exec SVC=gateway | make exec mysql | make exec localstack"
	@echo ""
	@echo "Tất cả stack (Makefile.all.mk):"
	@echo "  make stop-all | down-all  — stop / down shared + services"
	@echo "  make docker-stop-all      — dừng mọi container Docker đang chạy trên máy"
