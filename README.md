# grafana-stack 🏠📊

Full homelab monitoring stack for Chase's home server.

## What's included

| Service | Port | Purpose |
|---|---|---|
| Grafana | 3000 | Dashboards & alerts |
| Prometheus | 9090 | Metrics storage |
| Loki | 3100 | Log storage |
| Promtail | — | Log collector (Docker + files) |
| Node Exporter | 9100 | Host CPU/RAM/disk/network |
| cAdvisor | 8080 | Per-container metrics |
| ZFS Exporter | 9134 | Pool health, snapshots, capacity |
| Pushgateway | 9091 | Receives metrics from cron/backup scripts |

**Also scrapes:** OPNsense router at `10.0.0.1:9273` (requires os-telegraf plugin)

---

## First-time setup

### 1. Clone on your server
```bash
cd ~
git clone https://github.com/YOUR_USERNAME/grafana-stack.git
cd grafana-stack
```

### 2. Set up your .env
```bash
cp .env.example .env
nano .env
# Fill in your Grafana password and Discord webhook URL
```

### 3. Create the backup log directory
```bash
sudo mkdir -p /var/log/backups
```

### 4. Start the stack
```bash
docker compose up -d
```

### 5. Open Grafana
Go to `http://10.0.0.10:3000` in your browser.
Login with the credentials from your `.env` file.

### 6. Add Discord alert contact point
1. In Grafana → Alerting → Contact Points → New Contact Point
2. Type: Discord
3. Paste your webhook URL from `.env`
4. Test it — you should get a ping in your Discord channel

### 7. Import community dashboards (recommended)
These are pre-built dashboards you can import with one click in Grafana → Dashboards → Import:

| Dashboard | ID | What it shows |
|---|---|---|
| Node Exporter Full | `1860` | Host CPU, RAM, disk, network |
| Docker & cAdvisor | `193` | Per-container resource usage |
| Loki Logs | `13639` | Log explorer |
| ZFS | `10664` | Pool health and capacity |

---

## Updating your cron jobs to use the backup wrapper

Replace your existing cron entries with the wrapper script so backups get logged and push metrics to Grafana.

Current cron (what you have):
```
#0 1 * * 2 /bin/bash -c "/sbin/zfs snapshot -r tank@weekly-$(date +\%F)"
```

Updated cron (use this instead):
```
0 1 * * 2 /bin/bash /path/to/grafana-stack/scripts/zfs-backup-wrapper.sh tank weekly
15 1 1 * * /bin/bash /path/to/grafana-stack/scripts/zfs-backup-wrapper.sh tank monthly
0 1 * * 2 /bin/bash /path/to/grafana-stack/scripts/zfs-backup-wrapper.sh rpool weekly
15 1 1 * * /bin/bash /path/to/grafana-stack/scripts/zfs-backup-wrapper.sh rpool monthly
```

---

## OPNsense setup

To get router metrics into Grafana:

1. In OPNsense: **System → Firmware → Plugins** → install `os-telegraf`
2. Go to **Services → Telegraf**
3. Enable the service
4. Under Outputs, enable **Prometheus** on port `9273`
5. Prometheus will automatically scrape it every 15 seconds

---

## Git workflow

On your laptop:
```bash
# Make changes
git add .
git commit -m "your message"
git push
```

On your server:
```bash
cd ~/grafana-stack
git pull
docker compose up -d --force-recreate
```

---

## Adding more services later

To monitor a new service (e.g. Postgres, Redis, a custom app):
1. Add the exporter to `docker-compose.yml`
2. Add a scrape job to `prometheus/prometheus.yml`
3. Add alert rules to `alerting/`
4. `git push` → `git pull` on server → `docker compose up -d`
