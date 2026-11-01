#!/bin/bash
# (audit) 25 wrong codes from the same address at the same moment: exactly 10 are counted, the rest are refused
# usage: parallel-login-test.sh "<psql connection options for the support-center test database>"
# Only on a TEST database: it clears the login attempts before and after.
set -u
P="psql -q -X -At $1"
$P -c "delete from sc_login_attempts" >/dev/null
T="$(mktemp)"
for i in $(seq 1 25); do $P -c "select sc_login('wrong-code-$i') ->> 'error'" >> "$T" 2>&1 & done
wait
n_bad="$($P -c "select count(*) from sc_login_attempts where not ok")"
n_inv="$(grep -c '^code_invalid$' "$T")"; n_lim="$(grep -c '^rate_limited$' "$T")"
$P -c "delete from sc_login_attempts" >/dev/null
rm -f "$T"
if [ "$n_bad" = "10" ] && [ "$n_inv" = "10" ] && [ "$n_lim" = "15" ]; then
  echo "PASSED — 25 at once: 10 counted, 15 refused"
else
  echo "FAILED — counted $n_bad, code_invalid $n_inv, rate_limited $n_lim"; exit 1
fi
