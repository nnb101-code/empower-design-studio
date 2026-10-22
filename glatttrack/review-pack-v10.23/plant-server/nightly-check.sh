#!/bin/bash
# GlattTrack nightly check — runs before work (systemd timer gt-nightly.timer, e.g. 04:00).
# Checks the plant server end to end. Fixes ONLY what is safe to fix by itself (restart a stuck
# service, a fresh backup, room on the disk, the clock). Everything else is reported:
# the team leader sees it on "System health" in the morning, and GT_ALERT_CMD (optional) sends it out.
# It never changes kashrut data, settings, devices or workers.
. "$(dirname "$0")/gt-lib.sh"
D="$(cd "$(dirname "$0")" && pwd)"
set +eu +o pipefail                       # every check runs, whatever the one before it found
[ "$(gt_self_role)" = "primary" ] || { gt_log "nightly check: this server is the backup server — the main server checks"; exit 0; }

checks=(); problems=(); fixed=()
ok(){ checks+=("$1|ok|${2:-}"); }
bad(){ checks+=("$1|problem|$2"); problems+=("$1: $2"); gt_log "PROBLEM $1: $2"; }
fix(){ checks+=("$1|fixed|$2"); fixed+=("$1: $2"); gt_log "FIXED $1: $2"; }
PSQLV(){ "${GT_PSQL:-psql}" -X -q -t -A -h "$GT_PGHOST" -p "$GT_PG_PORT" -U "${GT_PGUSER:-postgres}" -d "$GT_DB" "$@"; }

# 1. the database answers, the expected schema step
step="$(PSQLV -c "select value from plant_state where key = 'schemaStep'" 2>/dev/null)"
if [ -z "$step" ]; then bad "מסד הנתונים" "לא עונה"; else
  [ "$step" -ge "${GT_EXPECT_STEP:-46}" ] 2>/dev/null && ok "מסד הנתונים" "שלב $step" || bad "מסד הנתונים" "שלב $step, צריך ${GT_EXPECT_STEP:-46}"; fi

# 2. the app's server (the API the tablets talk to) answers — a stuck service is restarted once
api_ok(){ [ -z "${GT_API_URL:-}" ] && return 0
  curl -s -m 8 -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' ${GT_API_KEY:+-H "apikey: $GT_API_KEY"} \
       "$GT_API_URL/rest/v1/rpc/server_now_ms" -d '{}' | grep -q '^2'; }
if api_ok; then ok "שרת האפליקציה" "עונה"
elif [ -n "${GT_API_RESTART_CMD:-}" ]; then
  eval "$GT_API_RESTART_CMD" >/dev/null 2>&1; sleep "${GT_API_RESTART_WAIT:-15}"
  if api_ok; then fix "שרת האפליקציה" "לא ענה — הופעל מחדש, עונה עכשיו"; else bad "שרת האפליקציה" "לא עונה, גם אחרי הפעלה מחדש — לקרוא למתקין"; fi
else bad "שרת האפליקציה" "לא עונה — לקרוא למתקין"; fi

# 3. the security self-test (03) — every protection still in place; it changes nothing (all undone).
#    Skipped while someone is working (an animal changed in the last 10 minutes).
if [ -n "${GT_SELFTEST_SQL:-}" ] && [ -f "$GT_SELFTEST_SQL" ]; then
  busy="$(PSQLV -c "select count(*) from animals_pilot where updated_at > now() - interval '10 minutes'" 2>/dev/null || echo 0)"
  if [ "${busy:-0}" -gt 0 ]; then ok "בדיקת אבטחה" "דולגה — יש עבודה עכשיו"
  else
    out="$("${GT_PSQL:-psql}" -X -h "$GT_PGHOST" -p "$GT_PG_PORT" -U "${GT_PGUSER:-postgres}" -d "$GT_DB" -f "$GT_SELFTEST_SQL" 2>&1)"
    line="$(echo "$out" | grep -o 'PASSED — [0-9]* of [0-9]*' | tail -1)"
    if [ -n "$line" ]; then ok "בדיקת אבטחה" "$line"; else bad "בדיקת אבטחה" "נכשלה — לקרוא למתקין: $(echo "$out" | grep -o 'FAILED[^(]*' | head -1 | cut -c1-300)"; fi
  fi
fi

# 4. the event log chain is unbroken
chain="$(PSQLV -c "select coalesce(verify_event_chain() ->> 'ok', 'false')" 2>/dev/null)"
[ "$chain" = "true" ] && ok "יומן האירועים" "השרשרת שלמה" || bad "יומן האירועים" "השרשרת שבורה — לקרוא למתקין"

# 5. a checked backup from the last 26 hours — if not, make one now
bk_ok(){ [ "$(PSQLV -c "select coalesce((select value from plant_state where key = 'lastBackupVerifiedAt')::timestamptz > now() - interval '26 hours', false)" 2>/dev/null)" = "t" ]; }
if bk_ok; then ok "גיבוי" "יש גיבוי בדוק מהיממה האחרונה"
else "$D/backup.sh" >/dev/null 2>&1
  if bk_ok; then fix "גיבוי" "לא היה גיבוי בדוק מהיממה האחרונה — נעשה עכשיו ונבדק"; else bad "גיבוי" "אין גיבוי בדוק — $(PSQLV -c "select value from plant_state where key = 'lastBackupFailReason'" 2>/dev/null)"; fi
fi

# 6. disk space (database and backup disk) — old backups and logs are cleared when space is short
free_pct(){ df -P "$1" 2>/dev/null | awk 'NR==2{gsub("%","",$5); print 100-$5}'; }
for target in "$GT_PGDATA" "$GT_BACKUP_DIR"; do
  [ -d "$target" ] || continue
  f="$(free_pct "$target")"; [ -z "$f" ] && continue
  if [ "$f" -ge "${GT_MIN_FREE_PCT:-15}" ]; then ok "מקום בדיסק" "$target: ${f}% פנוי"; continue; fi
  find "$GT_BACKUP_DIR" -name 'glatttrack-*.dump*' -mtime +"${GT_BACKUP_KEEP_MIN_DAYS:-7}" -delete 2>/dev/null
  journalctl --vacuum-time=14d >/dev/null 2>&1 || true
  f2="$(free_pct "$target")"
  if [ "${f2:-0}" -ge "${GT_MIN_FREE_PCT:-15}" ]; then fix "מקום בדיסק" "$target היה ${f}% פנוי — נמחקו גיבויים ויומנים ישנים, עכשיו ${f2}%"
  else bad "מקום בדיסק" "$target: רק ${f2}% פנוי — לפנות מקום או להחליף דיסק"; fi
done

# 7. the clock (rulings carry the time) — synced with the time server
if command -v chronyc >/dev/null 2>&1; then
  off="$(chronyc tracking 2>/dev/null | awk '/System time/{print $4}')"
  if [ -n "$off" ] && awk -v o="$off" 'BEGIN{exit !(o>2)}'; then
    chronyc makestep >/dev/null 2>&1
    off2="$(chronyc tracking 2>/dev/null | awk '/System time/{print $4}')"
    awk -v o="${off2:-99}" 'BEGIN{exit !(o<=2)}' && fix "שעון" "השעון סטה ב-${off} שניות — תוקן" || bad "שעון" "השעון סוטה ב-${off2} שניות"
  else ok "שעון" "סטייה ${off:-?} שניות"; fi
fi

# 8. the backup server streams (when the plant has one)
if [ "$(PSQLV -c "select coalesce((select value from plant_state where key = 'standbyExpected'), '')" 2>/dev/null)" = "1" ]; then
  n="$(PSQLV -c "select count(*) from pg_stat_replication where state = 'streaming'" 2>/dev/null || echo 0)"
  [ "${n:-0}" -gt 0 ] && ok "שרת חלופי" "מחובר" || bad "שרת חלופי" "לא מחובר"
fi

# 9. the UPS is on mains power
ups="$(PSQLV -c "select value from plant_state where key = 'upsStatus'" 2>/dev/null)"
[ -z "$ups" ] || { [ "$ups" = "online" ] && ok "חשמל (UPS)" "רשת חשמל רגילה" || bad "חשמל (UPS)" "$ups"; }

# 10. yesterday's board was closed (the daily reset is not waiting for a ruling)
w="$(PSQLV -c "select value from plant_state where key = 'rolloverWaitingSince'" 2>/dev/null)"
[ -z "$w" ] && ok "איפוס יומי" "בוצע" || bad "איפוס יומי" "ממתין מאז $w — יש בהמה בלי פסיקה אחרונה (ראש הצוות)"

# 11. tablets: paired station tablets not seen for a day
off_dev="$(PSQLV -c "select string_agg(coalesce(device_name, id) || ' (' || assigned_role || ')', ', ') from devices_pilot where assigned_role is not null and assigned_role <> 'leader' and coalesce(device_status, 'active') = 'active' and (last_seen is null or last_seen < now() - interval '24 hours')" 2>/dev/null)"
[ -z "$off_dev" ] && ok "טאבלטים" "כל הטאבלטים המצומדים נראו ביממה האחרונה" || bad "טאבלטים" "לא נראו יממה: $off_dev"

# 12. the https certificate (when the plant uses one) — at least 14 days left
if [ -n "${GT_TLS_CERT:-}" ] && [ -f "$GT_TLS_CERT" ]; then
  if openssl x509 -checkend $((14*86400)) -noout -in "$GT_TLS_CERT" >/dev/null 2>&1; then ok "תעודת https" "בתוקף ליותר מ-14 יום"
  else bad "תעודת https" "פגה בתוך 14 יום ($(openssl x509 -enddate -noout -in "$GT_TLS_CERT" | cut -d= -f2))"; fi
fi

# ── the report: where the team leader sees it, and out (optional) ──
js_arr(){ local first=1; printf '['; for x in "$@"; do [ $first = 1 ] || printf ','; first=0; printf '%s' "$x" | python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read()))'; done; printf ']'; }
js_checks(){ local first=1; printf '['; for c in "${checks[@]}"; do IFS='|' read -r k st msg <<<"$c"; [ $first = 1 ] || printf ','; first=0
  python3 -c 'import json,sys; sys.stdout.write(json.dumps({"k":sys.argv[1],"s":sys.argv[2],"m":sys.argv[3]}))' "$k" "$st" "$msg"; done; printf ']'; }
okflag=true; [ ${#problems[@]} -gt 0 ] && okflag=false
report="{\"at\":\"$(date -Iseconds)\",\"server\":\"${GT_SELF:-?}\",\"ok\":$okflag,\"problems\":$(js_arr "${problems[@]}"),\"fixed\":$(js_arr "${fixed[@]}"),\"checks\":$(js_checks)}"
gt_state nightlyCheck "$report"
gt_log "nightly check: ${#problems[@]} problems, ${#fixed[@]} fixed"
if [ -n "${GT_ALERT_CMD:-}" ] && { [ ${#problems[@]} -gt 0 ] || [ ${#fixed[@]} -gt 0 ]; }; then
  msg="GlattTrack ${GT_PLANT_NAME:-} — בדיקת לילה $(date '+%d/%m %H:%M')"
  [ ${#problems[@]} -gt 0 ] && msg="$msg
⚠ בעיות: $(printf '%s; ' "${problems[@]}")"
  [ ${#fixed[@]} -gt 0 ] && msg="$msg
✔ תוקן לבד: $(printf '%s; ' "${fixed[@]}")"
  GT_ALERT_TEXT="$msg" bash -c "$GT_ALERT_CMD" >/dev/null 2>&1 || gt_log "the alert could not be sent"
fi
[ ${#problems[@]} -eq 0 ]
