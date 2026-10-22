#!/bin/bash
# Makes THIS server the main server. Called by keepalived when this server takes the
# floating address (or by hand). Never makes a second main server: when the other
# server still answers as the main server, it refuses (no work rather than two truths).
. "$(dirname "$0")/gt-lib.sh"
me="$(gt_self_role)"
[ "$me" = "primary" ] && { gt_log "$GT_SELF is already the main server"; exit 0; }
[ "$me" = "standby" ] || { gt_log "Postgres on $GT_SELF does not answer — cannot take over"; exit 1; }
peer="$(gt_peer_role)"
if [ "$peer" = "primary" ]; then
  gt_log "REFUSED: the other server ($GT_PEER_IP) still answers as the main server — not promoting"
  exit 1
fi
if ! gt_net_ok; then
  gt_log "REFUSED: $GT_SELF cannot see the plant network (gateway $GT_GATEWAY_IP) — the problem is here, not at the main server"
  exit 1
fi
gt_log "the main server does not answer ($peer) — $GT_SELF becomes the main server"
gt_psql -c "select pg_promote(true, 30)" >/dev/null
for i in $(seq 1 30); do [ "$(gt_self_role)" = "primary" ] && break; sleep 1; done
[ "$(gt_self_role)" = "primary" ] || { gt_log "promotion did not finish"; exit 1; }
# no standby now: confirm rulings without waiting for one (the watchdog restores it when a standby joins)
gt_psql -c "alter system set synchronous_standby_names = ''" -c "select pg_reload_conf()" >/dev/null
gt_state lastFailoverAt "$(date -Iseconds)"
gt_state lastFailoverTo "$GT_SELF"
gt_log "$GT_SELF is the main server now"
