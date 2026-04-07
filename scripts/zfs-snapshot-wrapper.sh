#!/bin/bash
# ─────────────────────────────────────────────────────────────
# zfs-snapshot-wrapper.sh
#
# Drop-in wrapper for your existing ZFS cron jobs.
# - Logs SUCCESS/FAILED to /var/log/backups/zfs-snapshots.log
# - Pushes last_success timestamp to Pushgateway so Grafana
#   can alert if no backup has run in X days
#
# USAGE: Replace your cron commands with this script
# Example crontab entry:
#   0 1 * * 2 /opt/grafana-stack/scripts/zfs-snapshot-wrapper.sh weekly tank
#   15 1 1 * * /opt/grafana-stack/scripts/zfs-snapshot-wrapper.sh monthly tank
# ─────────────────────────────────────────────────────────────

SNAPSHOT_TYPE="${1:-manual}"   # weekly / monthly / daily
POOL="${2:-tank}"              # tank / rpool
LOG_DIR="/var/log/backups"
LOG_FILE="${LOG_DIR}/zfs-snapshots.log"
PUSHGATEWAY="http://10.0.0.10:9091"
DATE=$(date +%F)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Ensure log dir exists
mkdir -p "$LOG_DIR"

echo "[${TIMESTAMP}] Starting ZFS ${SNAPSHOT_TYPE} snapshot for pool: ${POOL}" >> "$LOG_FILE"

# ─── Create snapshot ─────────────────────────────────────────
/sbin/zfs snapshot -r "${POOL}@${SNAPSHOT_TYPE}-${DATE}"
SNAP_EXIT=$?

if [ $SNAP_EXIT -eq 0 ]; then
    echo "[${TIMESTAMP}] SUCCESS - Snapshot ${POOL}@${SNAPSHOT_TYPE}-${DATE} created" >> "$LOG_FILE"
else
    echo "[${TIMESTAMP}] FAILED - Snapshot creation failed for ${POOL}@${SNAPSHOT_TYPE}-${DATE} (exit: ${SNAP_EXIT})" >> "$LOG_FILE"
fi

# ─── Retention / cleanup ─────────────────────────────────────
case "$SNAPSHOT_TYPE" in
    weekly)  KEEP=4 ;;
    monthly) KEEP=6 ;;
    daily)   KEEP=7 ;;
    *)       KEEP=4 ;;
esac

/sbin/zfs list -t snapshot -o name -s creation \
    | grep "^${POOL}@${SNAPSHOT_TYPE}-" \
    | head -n -${KEEP} \
    | xargs -r /sbin/zfs destroy

DESTROY_EXIT=$?
if [ $DESTROY_EXIT -eq 0 ]; then
    echo "[${TIMESTAMP}] SUCCESS - Old ${SNAPSHOT_TYPE} snapshots pruned (keeping last ${KEEP})" >> "$LOG_FILE"
else
    echo "[${TIMESTAMP}] WARNING - Snapshot pruning had issues (exit: ${DESTROY_EXIT})" >> "$LOG_FILE"
fi

# ─── Push metric to Prometheus Pushgateway ───────────────────
# This lets Grafana alert if no backup runs in X days
if [ $SNAP_EXIT -eq 0 ]; then
    UNIX_TIMESTAMP=$(date +%s)
    cat <<EOF | curl -s --data-binary @- "${PUSHGATEWAY}/metrics/job/zfs_backup/pool/${POOL}/type/${SNAPSHOT_TYPE}"
# HELP backup_last_success_timestamp Unix timestamp of last successful backup
# TYPE backup_last_success_timestamp gauge
backup_last_success_timestamp ${UNIX_TIMESTAMP}
EOF
    echo "[${TIMESTAMP}] SUCCESS - Pushed success metric to Pushgateway" >> "$LOG_FILE"
fi

echo "[${TIMESTAMP}] ─────────────────────────────────────────" >> "$LOG_FILE"

exit $SNAP_EXIT
