#!/bin/bash
# GlattTrack — update the plant server (v10.35, owner: no team-leader approval, never harming the work).
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
ver_of(){ grep -o "var GT_APP_VERSION='[a-z][0-9][^']*';" "$1" 2>/dev/null | head -1 | sed "s/.*='\(.*\)';/\1/"; }

if [ "${1:-}" = "--rollback" ]; then
  [ -f "$APP.prev" ] || { say "nothing to roll back to ($APP.prev missing)"; exit 1; }
  cp -f "$APP.prev" "$APP.tmp" && mv -f "$APP.tmp" "$APP"
  gt_state appVersion "$(ver_of "$APP")"; gt_state appUpdatedAt "$(date -Is)"
  say "rolled back to $(ver_of "$APP") — the tablets go back by themselves"; exit 0
fi

NEW="${1:?usage: update-app.sh <new-app.html> [<new-02.sql>] | --rollback}"; SQL="${2:-}"
[ -f "$NEW" ] || { say "file not found: $NEW"; exit 1; }
NV="$(ver_of "$NEW")"; OV="$(ver_of "$APP")"
[ -n "$NV" ] || { say "not a GlattTrack app file (no version inside): $NEW"; exit 1; }
[ "$(gt_self_role)" = "primary" ] || { say "this is the backup server — update the main server"; exit 1; }

# 1. the server part (re-runnable), then the security self-test must pass
if [ -n "$SQL" ]; then
  [ -f "$SQL" ] || { say "file not found: $SQL"; exit 1; }
  PSQL -v ON_ERROR_STOP=1 -q -f "$SQL" >/dev/null 2>"/tmp/gt-update-02.err" || { say "02 FAILED — nothing changed for the tablets: $(tail -2 /tmp/gt-update-02.err)"; exit 2; }
fi
if [ -n "${GT_SELFTEST_SQL:-}" ] && [ -f "$GT_SELFTEST_SQL" ]; then
  out="$(PSQL -q -f "$GT_SELFTEST_SQL" 2>&1)"
  echo "$out" | grep -q 'PASSED — ' || { say "security self-test did NOT pass — the app was NOT updated (tablets stay on $OV)"; exit 3; }
fi

# 2. the app file: the old one kept for --rollback, the new one put in place in one step
cp -f "$APP" "$APP.prev" 2>/dev/null || true
cp -f "$NEW" "$APP.tmp" && mv -f "$APP.tmp" "$APP" || { say "could not write $APP"; exit 4; }
gt_state appVersion "$NV"; gt_state appUpdatedAt "$(date -Is)"
say "updated $OV → $NV (self-test passed). Tablets update by themselves; rollback: update-app.sh --rollback"
