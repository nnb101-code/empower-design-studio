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
GRACE="${GT_SYNC_GRACE:-6}"; STEP="${GT_SYNC_STEP:-2}"; down_since=""
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
  fi
  [ "${GT_ONCE:-}" = "1" ] && break
  sleep "$STEP"
done
