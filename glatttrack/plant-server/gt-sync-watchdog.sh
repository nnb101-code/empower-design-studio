#!/bin/bash
# Runs all the time on both servers (systemd). On the MAIN server only:
#  - FENCE: the other server took over while this one was cut off (it answers as the main
#    server with a higher timeline) → this server stops its Postgres at once, so tablets
#    can never write to two servers; it comes back only by rejoin-as-standby.sh
#  - the standby streams → rulings are confirmed only after the standby has them (no data loss)
#  - GT_SYNC_MODE=available: the standby is gone for more than GT_SYNC_GRACE seconds → the main
#    server confirms alone (work goes on; those rulings live on ONE server until the standby is back);
#    GT_SYNC_MODE=strict: never alone — work waits for the standby; system_health shows "standby_down"
. "$(dirname "$0")/gt-lib.sh"
GRACE="${GT_SYNC_GRACE:-6}"; STEP="${GT_SYNC_STEP:-2}"; down_since=""; app_check=0
# (full review P2) on the standby: the app file the main server installed (kept in the database, streamed here) is
# written to this server's own web folder — after a takeover the tablets load the same version
sync_app_file(){
  local f="${GT_APP_FILE:-}" want cur t
  [ -n "$f" ] || return 0
  want="$(gt_psql -c "select sha256 from plant_app_file where id = 1" 2>/dev/null)"
  [ -n "$want" ] || return 0
  cur="$( [ -f "$f" ] && sha256sum "$f" | cut -d' ' -f1 )"
  [ "$want" = "$cur" ] && return 0
  t="$(mktemp)"
  gt_psql -c "select body_b64 from plant_app_file where id = 1" 2>/dev/null | base64 -d > "$t" 2>/dev/null
  if [ "$(sha256sum "$t" | cut -d' ' -f1)" = "$want" ]; then
    [ -f "$f" ] && cp -f "$f" "$f.prev"
    chmod 644 "$t"; mv -f "$t" "$f" && gt_log "standby: app file updated to the main server's version"
  else rm -f "$t"; gt_log "standby: the app file from the database did not check (sha256) — not written"; fi
}
want="ANY 1 ($GT_STANDBY_APP)"
while true; do
  if [ "$(gt_self_role)" = "primary" ]; then
    if [ "$(gt_peer_role)" = "primary" ] && [ "$(gt_peer_tli)" -gt "$(gt_self_tli)" ]; then
      gt_log "FENCE: the other server ($GT_PEER_IP) is the main server now (newer timeline) — stopping Postgres on $GT_SELF; run rejoin-as-standby.sh --yes"
      mkdir -p /var/lib/glatttrack && date -Iseconds > /var/lib/glatttrack/needs-rejoin
      gt_pg_stop || true
      [ "${GT_ONCE:-}" = "1" ] && break
      sleep "$STEP"; continue
    fi
    cur="$(gt_psql -c "show synchronous_standby_names" 2>/dev/null || echo '?')"
    streaming="$(gt_psql -c "select count(*) from pg_stat_replication where application_name = '$GT_STANDBY_APP' and state = 'streaming'" 2>/dev/null || echo 0)"
    expected="$(gt_psql -c "select coalesce((select value from plant_state where key = 'standbyExpected'), '')" 2>/dev/null || echo '')"
    if [ "$streaming" -gt 0 ]; then
      down_since=""
      if [ "$cur" != "$want" ] && [ "$expected" = "1" ]; then
        gt_psql -c "alter system set synchronous_standby_names = '$want'" -c "select pg_reload_conf()" >/dev/null
        gt_log "standby back — rulings confirmed after the standby has them"
      fi
    else
      [ -z "$down_since" ] && down_since="$(date +%s)"
      if [ "${GT_SYNC_MODE:-available}" != "strict" ] && [ -n "$cur" ] && [ $(( $(date +%s) - down_since )) -ge "$GRACE" ]; then
        gt_psql -c "alter system set synchronous_standby_names = ''" -c "select pg_reload_conf()" >/dev/null
        gt_log "standby gone for ${GRACE}s — the main server confirms alone"
      fi
    fi
  else
    down_since=""
    if [ "$(gt_self_role)" = "standby" ] && [ $(( $(date +%s) - app_check )) -ge "${GT_APP_SYNC_EVERY:-60}" ]; then app_check=$(date +%s); sync_app_file; fi
  fi
  [ "${GT_ONCE:-}" = "1" ] && break
  sleep "$STEP"
done
