#!/bin/bash
# Run ONCE on the standby server (B), as root: copies the whole database from the
# main server and keeps receiving every change. ERASES this server's own database.
. "$(dirname "$0")/gt-lib.sh"
gt_check_secrets
[ "$(gt_peer_role)" = "primary" ] || { gt_log "the main server ($GT_PEER_IP) does not answer as the main server — stopping"; exit 1; }
[ "${1:-}" = "--yes" ] || { echo "This ERASES the database on this server ($GT_SELF) and copies it from $GT_PEER_IP. Run again with --yes."; exit 1; }
gt_log "copying the database from $GT_PEER_IP to $GT_SELF"
gt_pg_stop || true
rm -f /var/lib/glatttrack/needs-rejoin 2>/dev/null || true
[ -d "$GT_PGDATA" ] && mv "$GT_PGDATA" "$GT_PGDATA.old.$(date +%s)"
PGPASSWORD="$GT_REPL_PASS" "${GT_PG_BIN}/pg_basebackup" -h "$GT_PEER_IP" -p "${GT_PEER_PORT:-$GT_PG_PORT}" -U "$GT_REPL_USER" \
  -D "$GT_PGDATA" -X stream -R -c fast --checkpoint=fast -d "application_name=$GT_STANDBY_APP"
# the standby has its own name; when it becomes the main server it waits for no one until a new standby joins
CONF="$GT_PGDATA/postgresql.auto.conf"
sed -i '/^gt\.server_name/d' "$CONF"
echo "gt.server_name = '$GT_SELF'" >> "$CONF"
chown -R postgres:postgres "$GT_PGDATA" 2>/dev/null || true
chmod 700 "$GT_PGDATA"
gt_pg_start
sleep 3
gt_log "standby $GT_SELF: $(gt_self_role)"
