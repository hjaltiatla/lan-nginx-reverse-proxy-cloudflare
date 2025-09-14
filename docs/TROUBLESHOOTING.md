# Troubleshooting

**Container unhealthy**  
- Ensure `conf.d/20-http-redirect.conf` allows `127.0.0.1` for `/healthz` (or allow all for that location).
- Use the BusyBox healthcheck from the README.
- Tail logs: `docker logs -n 200 nginx-rproxy`

**Nginx restarts in a loop**  
Run a one-off syntax check to see the exact file:line:
```bash
docker run --rm   -v "$PWD/conf.d:/etc/nginx/conf.d:ro"   -v "$(docker volume ls -q | grep _letsencrypt):/etc/letsencrypt:ro"   nginx:1.27-alpine nginx -t
```
Fix the indicated file and retry.

**Cert cannot be read (unprivileged image)**  
If you switch to `nginxinc/nginx-unprivileged`, relax key perms:
```
chgrp 101 /etc/letsencrypt/live/hjalti.me/privkey.pem
chmod 640 /etc/letsencrypt/live/hjalti.me/privkey.pem
```
Add this as a certbot deploy hook so it persists across renewals.

**Proxmox returns 501 to HEAD**  
Use GET instead. In a browser it should load normally.

**Cloudflare token scope error**  
Add **Zone → Zone → Read** in addition to **Zone → DNS → Edit**, and limit scope to the single zone.
