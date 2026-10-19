#!/bin/bash
# GlattTrack — sign a release (round-2 review P-up1), on the manufacturer's computer that holds the private key:
#     bash release-sign.sh <version> <app.html> [<02.sql>] [--key gt-release-private.pem]
# Writes release-<version>.signed.json: what was signed (the version and the sha256 of each file) + the signature.
# Then: upload the files to https, and on the support-center page ("send an update") choose this file and give
# the two addresses. Each plant checks the signature with its public key and the files' sha256 before installing.
set -euo pipefail
KEY="gt-release-private.pem"; args=()
while [ $# -gt 0 ]; do case "$1" in --key) KEY="$2"; shift 2;; *) args+=("$1"); shift;; esac; done
V="${args[0]:-}"; APP="${args[1]:-}"; SQL="${args[2]:-}"
[[ "$V" =~ ^[a-z][0-9][0-9A-Za-z._-]{0,18}$ ]] || { echo "usage: release-sign.sh <version e.g. v10.39> <app.html> [<02.sql>] [--key file]" >&2; exit 2; }
[ -f "$APP" ] || { echo "app file not found: $APP" >&2; exit 2; }
[ -z "$SQL" ] || [ -f "$SQL" ] || { echo "server file not found: $SQL" >&2; exit 2; }
[ -f "$KEY" ] || { echo "private key not found: $KEY (make it once with release-key-new.sh)" >&2; exit 2; }
grep -q "var GT_APP_VERSION='$V';" "$APP" || { echo "the app file is not version $V (GT_APP_VERSION inside it)" >&2; exit 2; }
ASHA="$(sha256sum "$APP" | cut -d' ' -f1)"; SSHA="null"; [ -n "$SQL" ] && SSHA="\"$(sha256sum "$SQL" | cut -d' ' -f1)\""
# the signed text: one line, fixed order (the plant checks exactly these bytes)
M="{\"v\":1,\"version\":\"$V\",\"app\":\"$ASHA\",\"sql\":$SSHA,\"at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf '%s' "$M" > "$T/m"
openssl pkeyutl -sign -inkey "$KEY" -rawin -in "$T/m" -out "$T/s"
SIG="$(base64 -w0 < "$T/s")"
OUT="release-$V.signed.json"
printf '{"manifest":%s,"sig":"%s"}\n' "$(printf '%s' "$M" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" "$SIG" > "$OUT"
echo "signed: $OUT"
echo "  app $APP  sha256 $ASHA"
if [ -n "$SQL" ]; then echo "  02  $SQL  sha256 ${SSHA//\"/}"; fi
