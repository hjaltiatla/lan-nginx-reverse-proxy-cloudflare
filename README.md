# nginx-reverse-proxy-cloudflare (LAN-only, DNS-01)

Reverse proxy for a **home LAN** using **NGINX** and **Let's Encrypt** wildcard certs via **Cloudflare DNS-01**.
Nothing is exposed to the internet: traffic binds only to your LAN IP and each virtual host is allowlisted to
`192.168.144.0/24`.

**Highlights**
- Rootful `nginx:1.27-alpine` (simple cert permissions)
- Host ports **80/443** bound to `LAN_BIND` only → container listens on **8080/8443**
- Per-host servers for: `pfsense.hjalti.me`, `unifi.hjalti.me`, `pve.hjalti.me`, `plex.hjalti.me`
- **Wildcard** certificate for `hjalti.me` + `*.hjalti.me` (Cloudflare DNS token, least-privilege)
- `certbot` runs **on-demand** (no long-running container)
- Healthcheck hits `/healthz` on port 8080 (LAN-allowlisted + localhost allowed)
- Uses `http2 on;` (newer nginx syntax)

> For a full setup guide see **[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)** and **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)**.

---

## Quick start

1) **pfSense DNS Resolver → Host Overrides** (no WAN port-forwarding!)

   Point these names to your Docker host LAN IP (e.g., `192.168.144.50`):
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

3) **Start containers**
```bash
docker compose up -d
```

4) **Issue the wildcard certificate (DNS-01; outbound only)**
```bash
docker compose run --rm certbot certonly   --dns-cloudflare --dns-cloudflare-credentials /secrets/cloudflare.ini   -d hjalti.me -d '*.hjalti.me'   --agree-tos --email you@hjalti.me --no-eff-email --non-interactive

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
0 2,14 * * * cd /path/to/nginx-reverse-proxy-cloudflare &&   docker compose run --rm certbot renew     --dns-cloudflare --dns-cloudflare-credentials /secrets/cloudflare.ini     --quiet && docker exec nginx-rproxy nginx -s reload
```

---

## Repo layout (key files)

```
conf.d/
  00-global.conf
  20-http-redirect.conf          # allows 127.0.0.1 for healthcheck
  pfsense.hjalti.me.conf         # LAN-only
  unifi.hjalti.me.conf           # LAN-only + WebSockets
  pve.hjalti.me.conf             # LAN-only + WebSockets
  plex.hjalti.me.conf            # LAN-only + streaming opts
  includes/
    cloudflare-real-ip.conf      # optional (only if CF proxy is enabled; not used for LAN-only)
docker-compose.yml               # binds host 80/443 to LAN_BIND -> container 8080/8443
.env.example
secrets/cloudflare.ini.example
.github/workflows/ci.yml         # compose sanity + nginx -t with stub certs
```

---

## Notes

- The **healthcheck** in `docker-compose.yml` uses BusyBox `wget` inside the container and the redirect server allows
  `127.0.0.1` for `/healthz`, so it reports **healthy**.
- `http2 on;` is used per server (nginx ≥1.25 deprecates the `listen ... http2` flag).
- No WAN port-forwards are required; DNS-01 works via Cloudflare API + Let’s Encrypt.
