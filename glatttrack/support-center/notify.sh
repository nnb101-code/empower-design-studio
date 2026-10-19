#!/bin/bash
# GlattTrack support center — sends the alerts (v10.36). Every minute (cron / systemd timer) on any
# machine of the manufacturer that reaches the support-center database.
# Which channels: chosen on the support-center page (e-mail / SMS / WhatsApp, each on or off, with
# the addresses, and from which level: red only, or also orange). Settings of the senders: notify.env
#   CENTER_DB_URL=postgres://...            the support-center database (owner)
#   SMTP_URL=smtps://smtp.example.com:465   SMTP_USER=  SMTP_PASS=  MAIL_FROM=support@...
#   TWILIO_SID=  TWILIO_TOKEN=  SMS_FROM=+1...  WHATSAPP_FROM=+1...   (SMS and WhatsApp through Twilio)
#   DRY_RUN=1                               print instead of sending (tests)
set -u
ENV="${NOTIFY_ENV:-$(dirname "$0")/notify.env}"; [ -f "$ENV" ] && . "$ENV"
Q(){ psql "$CENTER_DB_URL" -X -q -t -A "$@"; }
Q -c "select _sc_check_silent()" >/dev/null                       # a plant that stopped reporting
declare -A HE=( [no_report]="המפעל לא מדווח (אין אינטרנט / השרת כבוי)" [standby_down]="שרת הגיבוי לא מחובר" [standby_lag]="שרת הגיבוי מפגר"
  [backup_stale]="אין גיבוי מאומת" [chain_broken]="יומן האירועים שבור" [nightly_check_problems]="בדיקת הלילה מצאה בעיות"
  [nightly_check_missing]="בדיקת הלילה לא רצה" [ups_on_battery]="אין חשמל — על סוללה" [ups_low_battery]="סוללת UPS כמעט ריקה"
  [devices_offline]="טאבלטים לא מחוברים" [tablet_offline_while_working]="טאבלט מנותק בזמן עבודה" [failed_logins]="הרבה כניסות שגויות"
  [revoked_device_writes]="מכשיר מנותק ניסה לכתוב" [rollover_waiting]="האיפוס היומי ממתין" [label_mismatch]="מדבקה שלא תואמת פסיקה" )
send_email(){ # $1 to, $2 text
  [ "${DRY_RUN:-}" = 1 ] && { echo "EMAIL → $1: $2"; return 0; }
  local mf; mf="$(mktemp)" || return 1                   # (round-2 review C-ntf1) a private temporary file
  printf 'From: %s\nTo: %s\nSubject: =?UTF-8?B?%s?=\nContent-Type: text/plain; charset=UTF-8\n\n%s\n' "$MAIL_FROM" "$1" \
    "$(printf 'GlattTrack — %s' "${2%%:*}" | base64 -w0)" "$2" > "$mf"
  curl -s -m 30 --ssl-reqd --url "$SMTP_URL" --user "$SMTP_USER:$SMTP_PASS" --mail-from "$MAIL_FROM" --mail-rcpt "$1" --upload-file "$mf"; local rc=$?
  rm -f "$mf"; return $rc; }
send_twilio(){ # $1 to, $2 from, $3 text
  [ "${DRY_RUN:-}" = 1 ] && { echo "MSG → $1 (from $2): $3"; return 0; }
  curl -s -m 30 -f -X POST "https://api.twilio.com/2010-04-01/Accounts/$TWILIO_SID/Messages.json" -u "$TWILIO_SID:$TWILIO_TOKEN" \
    --data-urlencode "To=$1" --data-urlencode "From=$2" --data-urlencode "Body=$3" >/dev/null; }
# settings: which channels, which addresses, from which level
read -r EON SON WON MIN <<<"$(Q -c "select (settings->'email'->>'on'), (settings->'sms'->>'on'), (settings->'whatsapp'->>'on'), settings->>'minLevel' from sc_notify where id = 1" | tr '|' ' ')"
mapfile -t ETO < <(Q -c "select jsonb_array_elements_text(settings->'email'->'to') from sc_notify where id = 1")
mapfile -t STO < <(Q -c "select jsonb_array_elements_text(settings->'sms'->'to') from sc_notify where id = 1")
mapfile -t WTO < <(Q -c "select jsonb_array_elements_text(settings->'whatsapp'->'to') from sc_notify where id = 1")
# the alerts not sent yet (and still open), red always, orange only when chosen
# (round-2 review C-ntf1) the fields come apart by a character that never appears in a plant name (not '|')
while IFS=$'\x1f' read -r id code name level text; do
  [ -n "$id" ] || continue
  [ "$level" = "warn" ] && [ "$MIN" != "warn" ] && { Q -c "update sc_alerts set sent = sent || '{\"skipped\":true}' where id = $id" >/dev/null; continue; }
  icon=$([ "$level" = bad ] && echo "🔴" || echo "🟠")
  msg="$icon מפעל #$code $name: ${HE[$text]:-$text}"
  # (full review C1) each recipient once: a channel / address that failed is tried again next minute,
  # the ones that already got it are not sent it again
  sent="$(Q -c "select sent::text from sc_alerts where id = $id")"; all=1
  mark(){ Q -c "update sc_alerts set sent = sent || jsonb_build_object('$1', now()::text) where id = $id" >/dev/null; }
  got(){ printf '%s' "$sent" | grep -qF "\"$1\""; }
  if [ "$EON" = true ]; then for t in "${ETO[@]}"; do k="email:$t"; got "$k" && continue; if send_email "$t" "$msg"; then mark "$k"; else all=0; fi; done; fi
  if [ "$SON" = true ]; then for t in "${STO[@]}"; do k="sms:$t"; got "$k" && continue; if send_twilio "$t" "${SMS_FROM:-}" "$msg"; then mark "$k"; else all=0; fi; done; fi
  if [ "$WON" = true ]; then for t in "${WTO[@]}"; do k="whatsapp:$t"; got "$k" && continue; if send_twilio "whatsapp:$t" "whatsapp:${WHATSAPP_FROM:-}" "$msg"; then mark "$k"; else all=0; fi; done; fi
  [ $all = 1 ] && mark at
done < <(Q -F $'\x1f' -c "select a.id, a.code, replace(p.name, chr(31), ' '), a.level, a.text from sc_alerts a join sc_plants p on p.code = a.code
               where a.resolved_at is null and not (a.sent ? 'at') and not (a.sent ? 'skipped') order by a.id")
