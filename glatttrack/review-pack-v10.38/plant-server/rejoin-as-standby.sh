#!/bin/bash
# After a takeover: the old main server comes back as the STANDBY of the new one.
# (It never becomes the main server again by itself.) ERASES its own database
# and copies it from the new main server.
. "$(dirname "$0")/gt-lib.sh"
[ "$(gt_peer_role)" = "primary" ] || { gt_log "the other server ($GT_PEER_IP) is not the main server — nothing to rejoin"; exit 1; }
exec "$(dirname "$0")/setup-standby.sh" "$@"
