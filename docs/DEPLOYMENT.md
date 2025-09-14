# Deployment (LAN-only, DNS-01)

This doc walks through a **fresh** deployment on a homelab host, with services reachable only from
`192.168.144.0/24`. The certificate is a **wildcard** for `hjalti.me` and `*.hjalti.me` using Cloudflare DNS-01.

## 1) Prereqs

- Docker & Docker Compose plugin installed
- A machine on the LAN (example host: `192.168.144.50`)
- Cloudflare account managing the **hjalti.me** zone
- **No** WAN port-forwarding for 80/443

## 2) DNS (split-horizon on pfSense)

pfSense → **Services → DNS Resolver → Host Overrides**:

| Hostname             | Value             |
|----------------------|-------------------|
| pfsense.hjalti.me    | 192.168.144.50    |
| unifi.hjalti.me      | 192.168.144.50    |
| pve.hjalti.me        | 192.168.144.50    |
| plex.hjalti.me       | 192.168.144.50    |

Ensure clients get pfSense as DNS via DHCP.

## 3) Checkout & configure

```bash
git clone https://github.com/<you>/nginx-reverse-proxy-cloudflare.git
cd nginx-reverse-proxy-cloudflare

cp .env.example .env
cp secrets/cloudflare.ini.example secrets/cloudflare.ini
chmod 600 secrets/cloudflare.ini
```

Edit `.env`:
```
LE_BASE_DOMAIN=hjalti.me
LAN_BIND=192.168.144.50
TZ=Atlantic/Reykjavik
```

Create a Cloudflare **API token** (My Profile → API Tokens → Create → *Edit zone DNS*):
- Permissions: **Zone → DNS → Edit**
- Zone Resources: **Include → Specific zone → hjalti.me**
Paste into `secrets/cloudflare.ini`:
```
dns_cloudflare_api_token = <token>
```

## 4) Start services

```bash
docker compose up -d
```

- `nginx` (rootful) binds host **80/443** to **LAN_BIND** → container **8080/8443**
- `certbot` is on-demand (runs only when you invoke `docker compose run`)

## 5) One-time certificate

```bash
docker compose run --rm certbot certonly   --dns-cloudflare --dns-cloudflare-credentials /secrets/cloudflare.ini   -d hjalti.me -d '*.hjalti.me'   --agree-tos --email you@hjalti.me --no-eff-email --non-interactive

docker exec nginx-rproxy nginx -t && docker exec nginx-rproxy nginx -s reload
```

## 6) Verify from LAN

```bash
curl -I https://pfsense.hjalti.me
curl -I https://unifi.hjalti.me
curl -I https://pve.hjalti.me     # HEAD may 501; GET returns 200
curl -I https://plex.hjalti.me
```

## 7) Renewal (cron on host)

```bash
crontab -e
```
Add:
```
0 2,14 * * * cd /path/to/nginx-reverse-proxy-cloudflare &&   docker compose run --rm certbot renew     --dns-cloudflare --dns-cloudflare-credentials /secrets/cloudflare.ini     --quiet && docker exec nginx-rproxy nginx -s reload
```

## 8) Healthcheck details

- `conf.d/20-http-redirect.conf` allows `127.0.0.1` on `/healthz` so the container can self-check.
- `docker-compose.yml` uses a BusyBox `wget` probe:
```yaml
healthcheck:
  test: ["CMD-SHELL", "/bin/busybox wget -q -O - http://127.0.0.1:8080/healthz >/dev/null 2>&1 || exit 1"]
  interval: 30s
  timeout: 5s
  retries: 5
  start_period: 10s
```

## 9) Security notes

- Each host server block includes:
```
allow 192.168.144.0/24;
deny  all;
```
- Keep the Cloudflare token scoped to **Zone.DNS:Edit** for the single zone.
- Back up the `/etc/letsencrypt` volume.

## 10) Updating

To update configs:
```bash
docker exec nginx-rproxy nginx -t && docker exec nginx-rproxy nginx -s reload
```
If you change `docker-compose.yml`:
```bash
docker compose up -d --force-recreate
```
