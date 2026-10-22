#!/bin/bash
# GlattTrack — update the plant server (v10.36, owner: no team-leader approval, never harming the work).
#   update-app.sh <new-app.html> [<new-02.sql>]   install a new version
#   update-app.sh --rollback                      back to the version before the last update
# Order: the server first (02, then the security self-test 03 must PASS), and only then the app file
# the tablets load. A tablet that finds the new file updates by itself when nobody works on it, or
# asks "update now / later" (the app does that). If anything fails, nothing changes for the tablets.
. "$(dirname "$0")/gt-lib.sh"
set -u
APP="${GT_APP_FILE:?set GT_APP_FILE in gt-plant.conf — the app file the web server serves}"
PSQL(){ "${GT_PSQL:-psql}" -X -h "$GT_PGHOST" -p "$GT_PG_PORT" -U "${GT_PGUSER:-postgres}" -d "$GT_DB" "$@"; }
say(){ echo "$*"; gt_log "update: $*"; }
# (full review P2) the same file goes into the database: the standby server's watchdog writes it to its own web
# folder, so after a takeover the tablets load the same version (not an older file left on the standby)
store_file(){ { printf '1\t%s\t%s\t' "$2" "$(sha256sum "$1" | cut -d' ' -f1)"; base64 -w0 "$1"; printf '\n'; } \
  | PSQL -q -v ON_ERROR_STOP=1 -c "begin; delete from plant_app_file; copy plant_app_file (id, version, sha256, body_b64) from stdin; commit;" >/dev/null 2>&1 \
  || gt_log "update: could not store the app file for the standby server (plant_app_file — run 02)"; }
ver_of(){ grep -o "var GT_APP_VERSION='[a-z][0-9][^']*';" "$1" 2>/dev/null | head -1 | sed "s/.*='\(.*\)';/\1/"; }

if [ "${1:-}" = "--rollback" ]; then
  [ -f "$APP.prev" ] || { say "nothing to roll back to ($APP.prev missing)"; exit 1; }
  cp -f "$APP.prev" "$APP.tmp" && mv -f "$APP.tmp" "$APP"
  gt_state appVersion "$(ver_of "$APP")"; gt_state appUpdatedAt "$(date -Is)"
  store_file "$APP" "$(ver_of "$APP")"
  # (audit) only the app goes back; the server part (02) stays — every 02 is made to work with the previous app
  say "rolled back to $(ver_of "$APP") — the tablets go back by themselves (the server part stays; it works with this app)"; exit 0
fi

NEW="${1:?usage: update-app.sh <new-app.html> [<new-02.sql>] | --rollback}"; SQL="${2:-}"
[ -f "$NEW" ] || { say "file not found: $NEW"; exit 1; }
NV="$(ver_of "$NEW")"; OV="$(ver_of "$APP")"
[ -n "$NV" ] || { say "not a GlattTrack app file (no version inside): $NEW"; exit 1; }
[ "$(gt_self_role)" = "primary" ] || { say "this is the backup server — update the main server"; exit 1; }

# 1. the server part and the security self-test in ONE transaction (full review P5): when the self-test does not
#    pass, the server part is undone too — the server stays exactly as it was. (Files are read by this shell and
#    piped in: the database's own user may not read root's temporary folder.)
if [ -n "$SQL" ]; then
  [ -f "$SQL" ] || { say "file not found: $SQL"; exit 1; }
  [ -n "${GT_SELFTEST_SQL:-}" ] && [ -f "$GT_SELFTEST_SQL" ] || { say "the security self-test file (GT_SELFTEST_SQL) is missing — a server part is never installed without it"; exit 3; }
  out="$(cat "$SQL" "$GT_SELFTEST_SQL" | PSQL -1 -v ON_ERROR_STOP=1 -q -f - 2>&1)" || true
  echo "$out" | grep -q 'PASSED — ' || { say "02 + security self-test did NOT pass — nothing changed (server and tablets stay on $OV): $(echo "$out" | grep -m1 -o 'ERROR.*\|FAILED.*' | cut -c1-300)"; exit 2; }
elif [ -n "${GT_SELFTEST_SQL:-}" ] && [ -f "$GT_SELFTEST_SQL" ]; then
  out="$(PSQL -q -f - < "$GT_SELFTEST_SQL" 2>&1)" || true
  echo "$out" | grep -q 'PASSED — ' || { say "security self-test did NOT pass — the app was NOT updated (tablets stay on $OV)"; exit 3; }
fi

# 2. the app file: the old one kept for --rollback, the new one put in place in one step
cp -f "$APP" "$APP.prev" 2>/dev/null || true
cp -f "$NEW" "$APP.tmp" && mv -f "$APP.tmp" "$APP" || { say "could not write $APP"; exit 4; }
gt_state appVersion "$NV"; gt_state appUpdatedAt "$(date -Is)"
store_file "$APP" "$NV"
say "updated $OV → $NV (self-test passed). Tablets update by themselves; rollback: update-app.sh --rollback"
