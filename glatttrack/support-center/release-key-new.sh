#!/bin/bash
# GlattTrack — the manufacturer's release signing key (round-2 review P-up1). Run ONCE, on the manufacturer's own
# computer (not the support center, not a plant server):
#     bash release-key-new.sh [folder]
# Makes:  gt-release-private.pem  — SECRET. Keep it on this computer / a USB stick in a safe. Never upload it.
#         gt-release-public.pem   — goes to EVERY plant server: /etc/glatttrack/release-public.pem
# A plant installs an update only when it is signed with this key: whoever gets into the support center cannot
# send his own code to the plants.
set -euo pipefail
D="${1:-.}"; umask 077
[ -e "$D/gt-release-private.pem" ] && { echo "$D/gt-release-private.pem already exists — not overwritten" >&2; exit 1; }
openssl genpkey -algorithm ed25519 -out "$D/gt-release-private.pem"
openssl pkey -in "$D/gt-release-private.pem" -pubout -out "$D/gt-release-public.pem"
chmod 600 "$D/gt-release-private.pem"; chmod 644 "$D/gt-release-public.pem"
echo "made: $D/gt-release-private.pem (SECRET — keep it safe, make one backup copy offline)"
echo "      $D/gt-release-public.pem  (copy to each plant server: /etc/glatttrack/release-public.pem)"
echo "fingerprint: $(openssl pkey -pubin -in "$D/gt-release-public.pem" -outform DER | sha256sum | cut -c1-16)"
