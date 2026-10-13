#!/bin/bash
# Nightly backup on the MAIN server to an external disk, CHECKED by restoring it into a scratch
# database (review A5: any restore error fails the backup; the restored copy must have the same
# schema step, at least the events that existed when the backup began, and an unbroken event chain).
# The result is what the team leader sees (system_health: backup).
. "$(dirname "$0")/gt-lib.sh"
[ "$(gt_self_role)" = "primary" ] || { gt_log "this server is the standby — the main server makes the backup"; exit 0; }
PSQL(){ "${GT_PSQL:-psql}" -X -q -t -A -v ON_ERROR_STOP=1 -h "$GT_PGHOST" -p "$GT_PG_PORT" -U "${GT_PGUSER:-postgres}" "$@"; }
v="gt_backup_verify"
cleanup(){ PSQL -d postgres -c "drop database if exists $v" >/dev/null 2>&1 || true; }
fail(){ cleanup; gt_state lastBackupFailedAt "$(date -Iseconds)"; gt_state lastBackupFailReason "$1"; gt_log "BACKUP FAILED: $1"; exit 1; }
mkdir -p "$GT_BACKUP_DIR" 2>/dev/null && [ -w "$GT_BACKUP_DIR" ] || fail "backup disk not available ($GT_BACKUP_DIR)"
f="$GT_BACKUP_DIR/glatttrack-$GT_SELF-$(date +%F-%H%M).dump"
ev_before="$(PSQL -d "$GT_DB" -c "select count(*) from events_pilot")" || fail "cannot read the live database"
live_step="$(PSQL -d "$GT_DB" -c "select value from plant_state where key = 'schemaStep'")"
"${GT_PG_BIN}/pg_dump" -h "$GT_PGHOST" -p "$GT_PG_PORT" -U "${GT_PGUSER:-postgres}" -Fc -f "$f" "$GT_DB" 2>"$f.dump.log" || fail "pg_dump (see $f.dump.log)"
# the check: a full restore into a scratch database — any error fails the backup
cleanup
PSQL -d postgres -c "create database $v" >/dev/null || fail "cannot create the scratch database"
"${GT_PG_BIN}/pg_restore" -h "$GT_PGHOST" -p "$GT_PG_PORT" -U "${GT_PGUSER:-postgres}" -d "$v" --no-owner --exit-on-error "$f" \
  >/dev/null 2>"$f.restore.log" || fail "pg_restore failed (see $f.restore.log)"
step="$(PSQL -d "$v" -c "select value from plant_state where key = 'schemaStep'" 2>/dev/null)"
[ -n "$step" ] && [ "$step" = "$live_step" ] || fail "restored schema step '$step' is not the live '$live_step'"
ev_after="$(PSQL -d "$v" -c "select count(*) from events_pilot" 2>/dev/null || echo -1)"
[ "$ev_after" -ge "$ev_before" ] || fail "restored copy has $ev_after events, the live database had $ev_before"
chain="$(PSQL -d "$v" -c "select coalesce((verify_event_chain() ->> 'ok'), 'false')" 2>/dev/null || echo error)"
[ "$chain" = "true" ] || fail "event chain in the restored copy: $chain"
cleanup
gt_state lastBackupVerifiedAt "$(date -Iseconds)"
gt_state_del lastBackupFailReason || true
rm -f "$f.restore.log" "$f.dump.log"
find "$GT_BACKUP_DIR" -name 'glatttrack-*.dump*' -mtime +"$GT_BACKUP_KEEP_DAYS" -delete 2>/dev/null || true
gt_log "backup ok and checked: $f ($(du -h "$f" | cut -f1); $ev_after events, chain ok)"
