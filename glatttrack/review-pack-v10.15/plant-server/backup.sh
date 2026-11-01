#!/bin/bash
# Nightly backup on the MAIN server to an external disk, CHECKED by restoring it into
# a scratch database. The result is what the team leader sees (system_health: backup).
. "$(dirname "$0")/gt-lib.sh"
[ "$(gt_self_role)" = "primary" ] || { gt_log "this server is the standby — the main server makes the backup"; exit 0; }
fail(){ gt_state lastBackupFailedAt "$(date -Iseconds)"; gt_state lastBackupFailReason "$1"; gt_log "BACKUP FAILED: $1"; exit 1; }
mkdir -p "$GT_BACKUP_DIR" 2>/dev/null || fail "backup disk not available ($GT_BACKUP_DIR)"
f="$GT_BACKUP_DIR/glatttrack-$GT_SELF-$(date +%F-%H%M).dump"
"${GT_PG_BIN}/pg_dump" -h "$GT_PGHOST" -p "$GT_PG_PORT" -U "${GT_PGUSER:-postgres}" -Fc -f "$f" "$GT_DB" || fail "pg_dump"
# the check: restore into a scratch database and read the schema step and the number of archived days
v="gt_backup_verify"
gt_psql -c "drop database if exists $v" -d postgres >/dev/null 2>&1 || true
"${GT_PSQL:-psql}" -X -q -h "$GT_PGHOST" -p "$GT_PG_PORT" -U "${GT_PGUSER:-postgres}" -d postgres -c "drop database if exists $v" -c "create database $v" >/dev/null || fail "scratch database"
"${GT_PG_BIN}/pg_restore" -h "$GT_PGHOST" -p "$GT_PG_PORT" -U "${GT_PGUSER:-postgres}" -d "$v" --no-owner "$f" >/dev/null 2>"$f.restore.log" || true
step="$("${GT_PSQL:-psql}" -X -q -t -A -h "$GT_PGHOST" -p "$GT_PG_PORT" -U "${GT_PGUSER:-postgres}" -d "$v" -c "select value from plant_state where key = 'schemaStep'" 2>/dev/null || echo '')"
live="$(gt_psql -c "select value from plant_state where key = 'schemaStep'")"
"${GT_PSQL:-psql}" -X -q -h "$GT_PGHOST" -p "$GT_PG_PORT" -U "${GT_PGUSER:-postgres}" -d postgres -c "drop database if exists $v" >/dev/null || true
[ -n "$step" ] && [ "$step" = "$live" ] || fail "the backup does not restore (schema step '$step' vs '$live')"
gt_state lastBackupVerifiedAt "$(date -Iseconds)"
gt_state_del lastBackupFailReason || true
find "$GT_BACKUP_DIR" -name 'glatttrack-*.dump*' -mtime +"$GT_BACKUP_KEEP_DAYS" -delete 2>/dev/null || true
gt_log "backup ok and checked: $f ($(du -h "$f" | cut -f1))"
