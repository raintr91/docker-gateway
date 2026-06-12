# Script tiện ích (gateway sites, hosts, SSL) — tại repo root.
# Được include từ Makefile — biến $(ROOT) do Makefile gốc định nghĩa trước.

.PHONY: gen-sites init-sites hosts gen-ssl certs-combined gw gw-safe ssl

# Chỉ copy gateway/sites.example → gateway/sites (infra: phpmyadmin, mail, mock, …).
init-sites:
	@mkdir -p "$(ROOT)/gateway/sites"
	@for f in "$(ROOT)/gateway/sites.example"/*.conf; do \
		[ -f "$$f" ] || continue; \
		base=$$(basename "$$f"); \
		if [ ! -f "$(ROOT)/gateway/sites/$$base" ]; then \
			cp "$$f" "$(ROOT)/gateway/sites/$$base"; \
			echo "[INFO] Copied $$base"; \
		fi; \
	done

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
