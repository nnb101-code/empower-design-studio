#!/bin/bash
# GlattTrack — sticker printing through the plant server (v10.38). Runs all the time (gt-print-relay.service),
# on the main server only. (1) Sends each new print job (ZPL from a station tablet, print_job_add) to its
# network printer, IP:9100, and marks it sent / failed. (2) When the team leader asks to search
# (printer_scan_request), looks on the plant's own network for label printers (port 9100) and leaves the list
# in plant_state 'printersFound'. Sends only to the plant's own network and a printer port — the same rule
# as the server (_printer_addr_ok).
. "$(dirname "$0")/gt-lib.sh"
set +e
ADDR_RE='^(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}):(9100|9101|9102|6101)$'
[ -n "${GT_PRINT_TEST_ADDR_RE:-}" ] && ADDR_RE="$GT_PRINT_TEST_ADDR_RE"   # tests only (a fake printer on this machine)
send_job(){   # $1 = id, $2 = ip:port
  local id="$1" ip="${2%:*}" port="${2##*:}" f rc err=""
  [[ "$2" =~ $ADDR_RE ]] || { gt_psql -c "update print_jobs set status = 'failed', error = 'address not allowed' where id = $id" >/dev/null; return; }
  f="$(mktemp)"
  gt_psql -c "select data from print_jobs where id = $id" | base64 -d > "$f" 2>/dev/null
  if [ ! -s "$f" ]; then err="empty job"
  else timeout 15 bash -c 'exec 3<>"/dev/tcp/$1/$2" && cat "$3" >&3' _ "$ip" "$port" "$f" 2>/dev/null; rc=$?
       [ $rc -eq 0 ] || err="printer $ip:$port does not answer (code $rc)"; fi
  rm -f "$f"
  if [ -z "$err" ]; then gt_psql -c "update print_jobs set status = 'sent', sent_at = now(), error = null where id = $id" >/dev/null
  else gt_psql -c "update print_jobs set status = 'failed', error = \$e\$$err\$e\$ where id = $id" >/dev/null; gt_log "print job $id: $err"; fi
}
scan(){
  local nets n ip found="" model
  nets="$( { ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1; hostname -I 2>/dev/null | tr ' ' '\n'; } | grep -E '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)' | sed 's/\.[0-9]*$//' | sort -u)"
  [ -n "${GT_PRINTER_NETS:-}" ] && nets="$GT_PRINTER_NETS"      # e.g. "192.168.10 192.168.11" (the first three numbers)
  for n in $nets; do
    found="$found $(seq 1 254 | xargs -P 64 -I{} bash -c 'timeout 0.5 bash -c "exec 3<>/dev/tcp/$0.{}/9100" 2>/dev/null && echo "$0.{}"' "$n")"
  done
  local lines=""
  for ip in $found; do
    # a Zebra / ZPL printer answers ~HI with its model (others stay silent — then only the address)
    model="$(timeout 3 bash -c 'exec 3<>"/dev/tcp/$0/9100"; printf "~HI\r\n" >&3; timeout 2 head -c 120 <&3' "$ip" 2>/dev/null | tr -cd '[:alnum:] ._,-' | cut -c1-60)"
    lines="$lines$ip|$model"$'\n'
  done
  # (psql substitutes :'l' only in what it reads, not in -c)
  gt_psql -v l="$lines" >/dev/null <<'SQL'
insert into plant_state (key, value)
select 'printersFound', jsonb_build_object('at', now(), 'printers', coalesce(jsonb_agg(jsonb_build_object('ip', split_part(x, '|', 1), 'port', 9100,
       'model', nullif(split_part(x, '|', 2), '')) order by x), '[]'::jsonb))::text
  from unnest(string_to_array(trim(:'l', E'\n'), E'\n')) x where x <> ''
on conflict (key) do update set value = excluded.value, updated_at = now();
SQL
  gt_log "printer search: $(echo $found | wc -w) found on: $nets"
}
last_beat=0
while true; do
  if [ "$(gt_self_role)" != "primary" ]; then sleep 5; continue; fi
  now=$(date +%s)
  if [ $((now - last_beat)) -ge 30 ]; then gt_state printRelayAt "$(date -Is)" >/dev/null; last_beat=$now; fi
  while read -r id printer; do [ -n "$id" ] && send_job "$id" "$printer"; done \
    < <(gt_psql -c "select id || ' ' || printer from print_jobs where status = 'new' order by id limit 50")
  if [ "$(gt_psql -c "select coalesce((select value::timestamptz from plant_state where key = 'printerScanRequestedAt')
                        > coalesce((select (value::jsonb ->> 'at')::timestamptz from plant_state where key = 'printersFound'), '-infinity'), false)")" = "t" ]; then
    scan
  fi
  sleep "${GT_PRINT_POLL:-0.5}"
done
