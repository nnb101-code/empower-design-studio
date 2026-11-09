#!/bin/bash
# (audit) actions at the same moment as the daily reset — through the real API, on a TEST database only
# (it resets the board and rules animals 7 and 8).
#   parallel-reset-test.sh "<psql options>" <API url> <outer tablet token>
# 1. a ruling sent while a reset is running waits for the reset, then is refused (it was for the old day) —
#    it never lands on the new day's animal with the same number
# 2. a ruling that started before the reset is finished first and kept in the archive of the old day
set -u
P="psql -q -X -At $1"; API="$2"; TOK="$3"
push(){   # $1 animal, $2 board epoch → the API's answer
  curl -s -m 30 -X POST "$API/rpc/animal_push" -H 'Content-Type: application/json' -H "x-device-token: $TOK" \
    -d "{\"p_rows\":{\"id\":$1,\"board_epoch\":$2,\"outer_status\":\"glatt\",\"outer_time\":$(date +%s%3N)}}"; }
prep(){ $P -c "begin; select set_config('gt.reset_in_progress','true',true);
  update animals_pilot set slaughter='slaughtered', slaughter_time=(extract(epoch from now())*1000)::bigint - 600000, eso_checked=true, eso_result='ok',
         legs_stickers=true, head_stickers=true, inner_status='confirmed', inner_time=(extract(epoch from now())*1000)::bigint - 300000
   where id in (7, 8); commit;" >/dev/null; }
# the reset exactly as the team leader's reset / the daily rollover do it: the reset lock first, then the reset
RESET="select pg_advisory_xact_lock(hashtext('glatttrack_daily_rollover')); select _do_board_reset('parallel test', null);"
fail=0
$P -c "begin; $RESET commit;" >/dev/null; prep
E1="$($P -c "select _board_epoch()")"

# 1. the reset holds its lock for 3 seconds; the ruling for animal 7 is sent 1 second in
( $P -c "begin; $RESET select pg_sleep(3); commit;" >/dev/null ) &
sleep 1; t0=$(date +%s%3N); R1="$(push 7 "$E1")"; t1=$(date +%s%3N); wait
E2="$($P -c "select _board_epoch()")"
S7="$($P -c "select coalesce(outer_status, '-') from animals_pilot where id = 7")"
if [ "$E2" != "$E1" ] && [ "$S7" = "-" ] && [ $((t1 - t0)) -ge 1000 ] && ! echo "$R1" | grep -q '"ok" *: *true'; then
  echo "PASS  1. a ruling during the reset waited $((t1 - t0)) ms and was refused for the old day; the new day's #8 is untouched: $(echo "$R1" | cut -c1-120)"
else echo "FAIL  1. epoch $E1→$E2, animal 7 '$S7', waited $((t1 - t0)) ms, answer: $R1"; fail=1; fi

# 2. a ruling whose transaction is still open when the reset starts: the reset waits for it, the ruling is kept
prep; E2="$($P -c "select _board_epoch()")"
( $P -c "begin; select _board_write_lock(); update animals_pilot set outer_status = 'glatt', outer_time = 1 where id = 8; select pg_sleep(2); commit;" >/dev/null ) &
sleep 0.5; t0=$(date +%s%3N); $P -c "begin; $RESET commit;" >/dev/null; t1=$(date +%s%3N); wait
K8="$($P -c "select coalesce((select a ->> 'outer_status' from daily_board_archive d, jsonb_array_elements(d.board) a
                              where (a ->> 'id')::int = 8 and a ->> 'board_epoch' = '$E2' limit 1), '-')")"
if [ $((t1 - t0)) -ge 1000 ] && [ "$K8" = "glatt" ]; then
  echo "PASS  2. the reset waited $((t1 - t0)) ms for the ruling in progress; the ruling is in the old day's archive"
else echo "FAIL  2. reset waited $((t1 - t0)) ms, archived ruling of #8: '$K8'"; fail=1; fi

$P -c "begin; $RESET commit;" >/dev/null
[ $fail = 0 ] && echo "PASSED — parallel reset test" || { echo "NOT PASSED"; exit 1; }
