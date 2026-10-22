#!/bin/bash
# GlattTrack — sign a request for a new manufacturer code (v10.38), on the manufacturer's computer that holds the
# release key (the same key as release-sign.sh):
#     bash maker-code-sign.sh maker-code-<plant>.json [--key gt-release-private.pem]
# The request file comes from the support-center page (plant → "🔑 new manufacturer code"): the plant number and the
# bcrypt hash of the new code, made in the browser — the code itself is in no file. Writes
# maker-code-<plant>.signed.json; choose it on the same page and send it. The plant server checks the signature,
# its own plant number and the time (at most 7 days old, and newer than the last one) before it changes the code.
set -euo pipefail
KEY="gt-release-private.pem"; args=()
while [ $# -gt 0 ]; do case "$1" in --key) KEY="$2"; shift 2;; *) args+=("$1"); shift;; esac; done
REQ="${args[0]:-}"
[ -f "$REQ" ] || { echo "usage: maker-code-sign.sh maker-code-<plant>.json [--key file]" >&2; exit 2; }
[ -f "$KEY" ] || { echo "private key not found: $KEY (make it once with release-key-new.sh)" >&2; exit 2; }
# the signed text: one line, fixed order, only the fields the plant reads — made here, not taken as written
M="$(python3 -I - "$REQ" <<'PY'
import json, re, sys
r = json.load(open(sys.argv[1], encoding='utf-8'))
plant, h = str(r.get('plant', '')), str(r.get('hash', ''))
if r.get('kind') != 'maker_code' or not re.fullmatch(r'[0-9]{3,8}', plant) or not re.fullmatch(r'\$2a\$1[0-2]\$[./A-Za-z0-9]{53}', h):
    sys.exit('this is not a manufacturer-code request from the support-center page')
import datetime
at = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
print(json.dumps({'v': 1, 'kind': 'maker_code', 'plant': plant, 'hash': h, 'at': at}, separators=(',', ':')), end='')
PY
)"
P="$(printf '%s' "$M" | python3 -I -c 'import json,sys; print(json.loads(sys.stdin.read())["plant"])')"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf '%s' "$M" > "$T/m"
openssl pkeyutl -sign -inkey "$KEY" -rawin -in "$T/m" -out "$T/s"
SIG="$(base64 -w0 < "$T/s")"
OUT="maker-code-$P.signed.json"
printf '{"manifest":%s,"sig":"%s"}\n' "$(printf '%s' "$M" | python3 -I -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" "$SIG" > "$OUT"
echo "signed: $OUT  (plant $P) — choose it on the support-center page and send; valid for 7 days"
