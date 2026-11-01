#!/bin/bash
# Called by NUT (upsmon NOTIFYCMD) on a UPS event: ONLINE, ONBATT, LOWBATT, ...
# Writes it where the team leader sees it (system_health: UPS on battery / low battery).
. "$(dirname "$0")/gt-lib.sh"
ev="${1:-${NOTIFYTYPE:-}}"
case "$ev" in
  ONLINE)  st=online ;;
  ONBATT)  st=onbattery ;;
  LOWBATT) st=lowbattery ;;
  *) gt_log "UPS event $ev (ignored)"; exit 0 ;;
esac
[ "$(gt_self_role)" = "primary" ] || { gt_log "UPS $st — this server is the standby (read-only), the main server reports its own UPS"; exit 0; }
gt_state upsStatus "$st"; gt_state upsAt "$(date -Iseconds)"
gt_log "UPS: $st"
