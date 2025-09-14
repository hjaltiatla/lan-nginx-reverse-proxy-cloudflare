# lan-nginx-reverse-proxy-cloudflare

Reverse proxy for a **home LAN** using **NGINX** and **Let’s Encrypt** wildcard certs via **Cloudflare DNS-01**.  
Designed for **LAN-only** access (no WAN port-forwarding). Each vhost is allowlisted to `192.168.144.0/24`.

**Highlights**
- Rootful `nginx:1.27-alpine` (simple cert permissions)
- Host ports **80/443** bound to `LAN_BIND` only → container listens on **8080/8443**
- Per-host servers: `pfsense.hjalti.me`, `unifi.hjalti.me`, `pve.hjalti.me`, `plex.hjalti.me`
- **Wildcard** certificate for `hjalti.me` + `*.hjalti.me` via Cloudflare DNS-01
- `certbot` runs **on-demand** (no long-running container)
- **Healthcheck uses `nginx -t`** (config test); `/healthz` is provided for manual checks
- Uses `http2 on;` (newer nginx syntax)

> Full guide: **[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)** • Troubleshooting: **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)**

---

## Quick start

1) **pfSense DNS → Host Overrides**  
   Point these to your Docker host LAN IP (e.g., `192.168.144.50`):
   - `pfsense.hjalti.me`, `unifi.hjalti.me`, `pve.hjalti.me`, `plex.hjalti.me` → `192.168.144.50`

2) **Configure env + secrets**
```bash
cp .env.example .env
cp secrets/cloudflare.ini.example secrets/cloudflare.ini
chmod 600 secrets/cloudflare.ini
# edit .env
#   LE_BASE_DOMAIN=hjalti.me
#   LAN_BIND=192.168.144.50
#   TZ=Atlantic/Reykjavik
# paste your Cloudflare token (Zone.DNS:Edit on hjalti.me) into secrets/cloudflare.ini:
#   dns_cloudflare_api_token = <token>
```

3) **Start services**
```bash
docker compose up -d
```

4) **Issue the wildcard certificate**
```bash
docker compose run --rm certbot certonly   --dns-cloudflare   --dns-cloudflare-credentials /secrets/cloudflare.ini   -d hjalti.me -d '*.hjalti.me'   --agree-tos --email you@hjalti.me --no-eff-email --non-interactive

docker exec nginx-rproxy nginx -t && docker exec nginx-rproxy nginx -s reload
```

5) **Verify from LAN**
```bash
curl -I https://pfsense.hjalti.me
curl -I https://unifi.hjalti.me
curl -I https://pve.hjalti.me     # Proxmox may 501 on HEAD; GET returns 200
curl -I https://plex.hjalti.me
```

6) **Auto-renew (cron on the Docker host)**
```bash
crontab -e
```
Add:
```
0 2,14 * * * cd /path/to/lan-nginx-reverse-proxy-cloudflare &&   docker compose run --rm certbot renew     --dns-cloudflare --dns-cloudflare-credentials /secrets/cloudflare.ini     --quiet && docker exec nginx-rproxy nginx -s reload
```

---

## Healthcheck

- **Docker healthcheck:** uses a configuration test (robust across environments):
```yaml
healthcheck:
  test: ["CMD", "nginx", "-t"]
  interval: 30s
  timeout: 5s
  retries: 5
  start_period: 10s
```
- **Manual check (from host/LAN):** `/healthz` returns `ok` on port 8080:
```bash
curl -s http://$LAN_BIND/healthz
```

---

## Repo layout (key files)

```
conf.d/
  00-global.conf
  20-http-redirect.conf          # /healthz (200) + redirect everything else → HTTPS
  pfsense.hjalti.me.conf         # LAN-only
  unifi.hjalti.me.conf           # LAN-only + WebSockets
  pve.hjalti.me.conf             # LAN-only + WebSockets
  plex.hjalti.me.conf            # LAN-only + streaming opts
  includes/
    cloudflare-real-ip.conf      # optional (if ever proxying via Cloudflare)
docker-compose.yml               # binds host 80/443 to LAN_BIND -> container 8080/8443
.env.example
secrets/cloudflare.ini.example
docs/DEPLOYMENT.md
docs/TROUBLESHOOTING.md
Makefile                          # helper targets (up/down/reload/issue-cert/renew/...)
```

---

## Notes
- Keep the Cloudflare token **scoped to a single zone** with **Zone → DNS → Edit** privileges.
- No WAN port-forward is required; DNS-01 works with outbound-only API calls.
- Back up the Let’s Encrypt Docker volume (`letsencrypt-backup.tgz` via `make backup-certs`).

---

## License
MIT
