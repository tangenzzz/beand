# Hosting beand.app on Hetzner

One small Hetzner Cloud server runs everything: Caddy (TLS, static files, catalog API) and a tiny Node process for on-demand pages (`/s/*` shared shots).

```
Internet ──▶ Caddy :443 ─┬─ /api/*  → /srv/beand/api/          (catalog, static, deployed by the catalog workflow)
                         ├─ /s/*    → 127.0.0.1:4321 (Node)    (shared shots, server-rendered for link previews)
                         └─ /*      → /srv/beand/site/current/client  (prebuilt Astro pages)
```

## 1. Server

- Hetzner Cloud, smallest shared x86 or Arm instance, location Falkenstein/Nuremberg (DE) or Helsinki, Ubuntu 24.04.
- Add your SSH key at creation. Enable backups (or snapshots) in the console.
- Hetzner Cloud Firewall: allow inbound 22, 80, 443 (TCP) and 443 (UDP, HTTP/3). Nothing else.
- Sign Hetzner's data processing agreement (AVV) in the console — the privacy policy refers to it.

## 2. DNS

At the registrar (or Hetzner DNS). On Cloudflare set every record to **DNS only** (grey cloud) — Caddy terminates TLS itself:

| Name | Type | Value |
|---|---|---|
| `beand.app` | A / AAAA | server IPv4 / IPv6 |
| `www.beand.app` | CNAME | `beand.app` |
| `beand.app` | CAA | `0 issue "letsencrypt.org"` |

`.app` is HSTS-preloaded: browsers only ever use HTTPS. Caddy gets the certificate automatically once DNS points at the server.

## 3. Base setup (as root)

```bash
apt update && apt full-upgrade -y
apt install -y unattended-upgrades rsync debian-keyring debian-archive-keyring apt-transport-https curl
dpkg-reconfigure -plow unattended-upgrades

# SSH: keys only
# (Ubuntu's 50-cloud-init.conf re-enables passwords, so use a drop-in that sorts first)
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin prohibit-password\n' > /etc/ssh/sshd_config.d/00-keys-only.conf
sshd -t && systemctl reload ssh

# Swap: the CPX02 has only 1 GB RAM
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Node 22
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && apt install -y nodejs

# Caddy (official repo)
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
apt update && apt install -y caddy
```

## 4. Users and folders

```bash
useradd --system --home /srv/beand --shell /usr/sbin/nologin beand    # runs the Node server
useradd --create-home --shell /bin/bash deploy                        # used by GitHub Actions
mkdir -p /srv/beand/site/releases /srv/beand/api
chown -R deploy:deploy /srv/beand

# deploy may restart the site service, nothing else
echo 'deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart beand-site' > /etc/sudoers.d/deploy
chmod 440 /etc/sudoers.d/deploy

# SSH key for GitHub Actions (generate locally: ssh-keygen -t ed25519 -f beand-deploy -N "")
mkdir -p /home/deploy/.ssh && nano /home/deploy/.ssh/authorized_keys   # paste beand-deploy.pub
chown -R deploy:deploy /home/deploy/.ssh && chmod 700 /home/deploy/.ssh && chmod 600 /home/deploy/.ssh/authorized_keys
```

## 5. Caddy and service

```bash
cp deploy/Caddyfile /etc/caddy/Caddyfile
echo 'ACME_EMAIL=you@example.com' > /etc/default/caddy         # contact for Let's Encrypt
# the packaged caddy.service does not read /etc/default/caddy by itself
mkdir -p /etc/systemd/system/caddy.service.d
printf '[Service]\nEnvironmentFile=/etc/default/caddy\n' > /etc/systemd/system/caddy.service.d/env.conf
mkdir -p /var/log/caddy && chown -R caddy:caddy /var/log/caddy   # re-run after `caddy validate` as root
systemctl daemon-reload && systemctl restart caddy

cp deploy/beand-site.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable beand-site
# first start happens with the first deploy
```

## 6. Visitor statistics (GoAccess)

No script on the page, no cookies: GoAccess reads Caddy's access log once a night and writes an HTML report. IP addresses are anonymised (last octet / last 80 bits zeroed) before they are stored; the aggregated numbers are kept beyond the 14-day log retention.

```bash
apt install -y goaccess
mkdir -p /srv/beand/stats /var/lib/goaccess && chmod 755 /srv/beand/stats
cat > /etc/cron.d/beand-stats <<'CRON'
15 3 * * * root goaccess /var/log/caddy/beand.log --log-format=CADDY --anonymize-ip --persist --restore --db-path=/var/lib/goaccess --ignore-crawlers --exclude-ip=127.0.0.1 -o /srv/beand/stats/index.html >/dev/null 2>&1
CRON

# Password for https://beand.app/stats/ (user `matthias`). Set it BEFORE installing the new Caddyfile,
# Caddy refuses to start with an empty hash.
caddy hash-password                                  # type the password twice, copy the $2a$… hash
echo 'STATS_HASH=<hash>' >> /etc/default/caddy        # keep the single quotes, the hash contains $
cp deploy/Caddyfile /etc/caddy/Caddyfile && caddy validate --config /etc/caddy/Caddyfile
chown -R caddy:caddy /var/log/caddy && systemctl restart caddy
```

Run the cron line once by hand to get the first report immediately. `/stats/` is excluded in `robots.txt`.

## 7. GitHub secrets

Repository → Settings → Secrets and variables → Actions:

| Secret | Value |
|---|---|
| `DEPLOY_HOST` | `beand.app` (or the IP) |
| `DEPLOY_USER` | `deploy` |
| `DEPLOY_SSH_KEY` | contents of the private key `beand-deploy` |
| `DEPLOY_KNOWN_HOSTS` | output of `ssh-keyscan beand.app` |

Push to `main` (changes under `site/`) or run the workflow manually. Each deploy goes to a new folder under `releases/`, the `current` symlink is switched atomically, the last 5 releases are kept.

**Rollback:** `ln -sfn /srv/beand/site/releases/<older> /srv/beand/site/current && sudo systemctl restart beand-site`

## Later

- The catalog workflow deploys `catalog.json` to `/srv/beand/api/v1/` with the same SSH key (rsync), never into `site/`.
- Own Nostr relay (e.g. `strfry`) can run on the same box behind Caddy at `relay.beand.app`.
- Uptime check: any free external monitor on `https://beand.app/` and `/api/v1/catalog.json`.
