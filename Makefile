# Simple helpers for lan-nginx-reverse-proxy-cloudflare
# Usage: make <target>
# Override vars like: make issue-cert DOMAIN=hjalti.me EMAIL=you@hjalti.me

# ----- Config (override on the command line if needed) -----
NGINX ?= nginx-rproxy
DOMAIN ?= hjalti.me
EMAIL  ?= hjalti@hjalti.me
CF_CREDS ?= secrets/cloudflare.ini
NGINX_IMAGE ?= nginx:1.27-alpine

# ----- Targets -----
.PHONY: help up down restart reload logs tail validate config issue-cert renew renew-dry-run backup-certs health

help:
	@echo "Targets:"
	@echo "  up               - docker compose up -d"
	@echo "  down             - docker compose down"
	@echo "  restart          - recreate nginx service"
	@echo "  reload           - nginx -t && nginx -s reload inside container"
	@echo "  logs             - last 200 lines from nginx"
	@echo "  tail             - follow nginx logs"
	@echo "  validate         - nginx -t using a one-off container (mounts conf.d and LE volume)"
	@echo "  config           - docker compose config -q"
	@echo "  issue-cert       - Issue wildcard cert for $(DOMAIN) and *.$(DOMAIN) (DNS-01 via Cloudflare)"
	@echo "  renew            - Renew certs (quiet) and reload nginx"
	@echo "  renew-dry-run    - Dry-run renewal against staging"
	@echo "  backup-certs     - Tar.gz backup of the letsencrypt docker volume to letsencrypt-backup.tgz"
	@echo "  health           - Probe /healthz inside the container"

up:
	docker compose up -d

down:
	docker compose down

restart:
	docker compose up -d --force-recreate nginx

reload:
	docker exec $(NGINX) nginx -t && docker exec $(NGINX) nginx -s reload

logs:
	docker logs -n 200 $(NGINX)

tail:
	docker logs -f $(NGINX)

validate:
	@VOL=$$(docker volume ls -q | grep _letsencrypt) ; \
	docker run --rm -v "$$PWD/conf.d:/etc/nginx/conf.d:ro" -v "$$VOL:/etc/letsencrypt:ro" $(NGINX_IMAGE) nginx -t

config:
	docker compose config -q

issue-cert:
	docker compose run --rm certbot certonly \
	  --dns-cloudflare --dns-cloudflare-credentials /$(CF_CREDS) \
	  -d $(DOMAIN) -d '*.$(DOMAIN)' \
	  --agree-tos --email $(EMAIL) --no-eff-email --non-interactive
	$(MAKE) reload

renew:
	docker compose run --rm certbot renew \
	  --dns-cloudflare --dns-cloudflare-credentials /$(CF_CREDS) \
	  --quiet
	$(MAKE) reload

renew-dry-run:
	docker compose run --rm certbot renew \
	  --dns-cloudflare --dns-cloudflare-credentials /$(CF_CREDS) \
	  --dry-run

backup-certs:
	@VOL=$$(docker volume ls -q | grep _letsencrypt) ; \
	docker run --rm -v $$VOL:/le -v "$$PWD:/backup" alpine \
	  tar czf /backup/letsencrypt-backup.tgz -C / le ; \
	echo "Wrote $$PWD/letsencrypt-backup.tgz"

health:
	docker exec $(NGINX) /bin/busybox wget -q -O - http://127.0.0.1:8080/healthz >/dev/null && echo "OK" || (echo "FAIL" && exit 1)
