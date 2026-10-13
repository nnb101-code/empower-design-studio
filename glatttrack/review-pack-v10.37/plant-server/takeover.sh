#!/bin/bash
# The backup server becomes the main server — by a person, after checking the main server is OFF.
. "$(dirname "$0")/gt-lib.sh"
peer="$(gt_peer_role)"
if [ "$peer" = "primary" ]; then echo "The main server ($GT_PEER_IP) still answers — it is NOT off. Nothing done."; exit 1; fi
cat <<MSG
The backup server ($GT_SELF) will become the main server.
BEFORE this: the main server ($GT_PEER_IP) must be OFF — switched off, or its network cable unplugged.
If it is only cut off from this server but still reachable by the tablets, there would be two main servers.
Type the word  OFF  to confirm the main server is off:
MSG
read -r ans
[ "$ans" = "OFF" ] || { echo "Not confirmed. Nothing done."; exit 1; }
exec "$(dirname "$0")/promote.sh" --confirmed-other-is-off
