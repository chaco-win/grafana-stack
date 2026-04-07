#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# zfs-backup-wrapper.sh
# Wraps your existing ZFS snapshot cron jobs with logging + Prometheus metrics
#
# Usage: Replace your cron job commands with this script
# Example cron: 0 1 * * 2 /opt/grafana-stack/scripts/zfs-backup-wrapper.sh tank weekly
# ──────────────────────────────────────────────────────────────────────────────

POOL="${1:-tank}"
TYPE="${2:-weekly}"
LOG_DIR="/var/log/backups"
LOG_FILE="$LOG_DIR/zfs-${POOL}-${TYPE}.log"
PUSHGATEWAY="http://localhost:9091"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
DATE_TAG=$(date +%F)

mkdir -p "$LOG_DIR"

echo "[$TIMESTAMP] ── ZFS $TYPE snapshot starting for $POOL ──" >> "$LOG_FILE"

# ── Take the snapshot ──────────────────────────────────────────────────────────
SNAPSHOT_NAME="${POOL}@${TYPE}-${DATE_TAG}"
/sbin/zfs snapshot -r "$SNAPSHOT_NAME" >> "$LOG_FILE" 2>&1
SNAP_STATUS=$?

if [ $SNAP_STATUS -eq 0 ]; then
  echo "[$TIMESTAMP] SUCCESS: Created snapshot $SNAPSHOT_NAME" >> "$LOG_FILE"
  BACKUP_STATUS=1
else
  echo "[$TIMESTAMP] FAILED: Could not create snapshot $SNAPSHOT_NAME (exit code $SNAP_STATUS)" >> "$LOG_FILE"
  BACKUP_STATUS=0
fi

# ── Prune old snapshots ────────────────────────────────────────────────────────
if [ "$TYPE" = "weekly" ]; then
  KEEP=4
elif [ "$TYPE" = "monthly" ]; then
  KEEP=6
else
  KEEP=7
fi

echo "[$TIMESTAMP] Pruning old $TYPE snapshots (keeping $KEEP)..." >> "$LOG_FILE"
/sbin/zfs list -t snapshot -o name -s creation \
  | grep "^${POOL}@${TYPE}-" \
  | head -n -${KEEP} \
  | xargs -r /sbin/zfs destroy >> "$LOG_FILE" 2>&1

echo "[$TIMESTAMP] Pruning complete" >> "$LOG_FILE"

# ── Push metrics to Prometheus Pushgateway ─────────────────────────────────────
cat <<EOF | curl -s --data-binary @- "${PUSHGATEWAY}/metrics/job/zfs-backup/instance/${POOL}-${TYPE}"
# HELP backup_last_status Last backup result (1=success, 0=failure)
# TYPE backup_last_status gauge
backup_last_status{pool="${POOL}",type="${TYPE}"} ${BACKUP_STATUS}
# HELP backup_last_run_timestamp Unix timestamp of last backup attempt
# TYPE backup_last_run_timestamp gauge
backup_last_run_timestamp{pool="${POOL}",type="${TYPE}"} $(date +%s)
EOF

echo "[$TIMESTAMP] ── Done ──" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

exit $SNAP_STATUS
