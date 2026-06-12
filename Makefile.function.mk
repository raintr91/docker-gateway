# Script tiện ích (gateway sites, hosts, SSL) — tại repo root.
# Được include từ Makefile — biến $(ROOT) do Makefile gốc định nghĩa trước.

.PHONY: gen-sites hosts gen-ssl certs-combined gw gw-safe ssl

gen-sites:
	bash "$(ROOT)/gen-gateway-sites.sh" "$(ROOT)/.env"

hosts:
	bash "$(ROOT)/print-hosts-from-env.sh" "$(ROOT)/.env"

gen-ssl:
	bash "$(ROOT)/gen-dev-ssl.sh" "$(ROOT)/.env" "$(ROOT)/certs"
	bash "$(ROOT)/certs/refresh-combined-ca.sh"

certs-combined:
	bash "$(ROOT)/certs/refresh-combined-ca.sh"

gw: gen-sites

gw-safe: gen-sites
	docker compose --project-directory "$(ROOT)" up -d gateway-nginx
	docker compose --project-directory "$(ROOT)" exec -T gateway-nginx nginx -t

ssl: gen-ssl
