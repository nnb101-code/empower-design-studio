#!/bin/bash
# Makes THIS server (the backup) the main server. NOT automatic (review A3): two servers that only
# lost sight of each other must never both become the main server. So a person first makes sure the
# other server is really off (switched off / unplugged), then runs:
#     sudo /opt/glatttrack/plant-server/takeover.sh
# (takeover.sh asks to confirm and calls this with --confirmed-other-is-off).
# The floating address follows by itself: only the main server may hold it (keepalived/check_pg.sh).
. "$(dirname "$0")/gt-lib.sh"
if [ "${1:-}" != "--confirmed-other-is-off" ] && [ "${GT_AUTO_PROMOTE:-0}" != "1" ]; then
  gt_log "not promoting by itself (GT_AUTO_PROMOTE=0) — check the main server is off, then run takeover.sh"
  exit 1
fi
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
gt_log "the main server does not answer ($peer) and was confirmed off — $GT_SELF becomes the main server"
gt_psql -c "select pg_promote(true, 30)" >/dev/null
for i in $(seq 1 30); do [ "$(gt_self_role)" = "primary" ] && break; sleep 1; done
[ "$(gt_self_role)" = "primary" ] || { gt_log "promotion did not finish"; exit 1; }
# no backup server now: in "available" mode confirm alone; in "strict" mode a new backup server must join first
if [ "${GT_SYNC_MODE:-available}" != "strict" ]; then
  gt_psql -c "alter system set synchronous_standby_names = ''" -c "select pg_reload_conf()" >/dev/null
fi
gt_state lastFailoverAt "$(date -Iseconds)"
gt_state lastFailoverTo "$GT_SELF"
gt_log "$GT_SELF is the main server now"
