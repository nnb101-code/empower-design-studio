#!/bin/bash
# GlattTrack — report to the manufacturer's support center (v10.36). Every 5 minutes (systemd timer
# gt-report.timer). Sends the plant's health (_plant_report: no kashrut data, no names, no codes;
# v10.38: + the problem reports and the daily totals for billing),
# gets back the support center's commands and the current release, and carries them out:
#   restart_standby · reload_tablets · run_nightly_check · update_now
#   a new release → downloaded over https, sha256 checked, installed with update-app.sh (02 + the
#   security self-test first; a release with a server part waits until nobody works).
# Without internet nothing breaks: the plant works on; the support center shows "no report".
. "$(dirname "$0")/gt-lib.sh"
set +e
D="$(cd "$(dirname "$0")" && pwd)"
[ -n "${GT_CENTER_URL:-}" ] && [ -n "${GT_PLANT_CODE:-}" ] && [ -n "${GT_PLANT_SECRET:-}" ] || exit 0
[ "$(gt_self_role)" = "primary" ] || exit 0
# the old anon key (a JWT, eyJ...) also goes as Bearer; a new publishable key (sb_publishable_...) only as apikey
AUTH=(); case "${GT_CENTER_KEY:-}" in eyJ*) AUTH=(-H "Authorization: Bearer $GT_CENTER_KEY");; esac
RPC(){ curl -s -m 20 -X POST -H 'Content-Type: application/json' -H "apikey: $GT_CENTER_KEY" ${AUTH[@]+"${AUTH[@]}"} \
            "$GT_CENTER_URL/rest/v1/rpc/$1" --data-binary @-; }
J(){ "${GT_PSQL:-psql}" -X -q -t -A -h "$GT_PGHOST" -p "$GT_PG_PORT" -U "${GT_PGUSER:-postgres}" -d "$GT_DB" "$@"; }

body="$(J -v code="$GT_PLANT_CODE" -v sec="$GT_PLANT_SECRET" <<'SQL'
select jsonb_build_object('p_code', :'code', 'p_secret', :'sec', 'p_report', _plant_report());
SQL
)"
resp="$(printf '%s' "$body" | RPC sc_report)"
ok="$(J -v r="$resp" <<'SQL'
select coalesce((nullif(:'r', '')::jsonb ->> 'ok')::boolean, false);
SQL
)"
[ "$ok" = "t" ] || { gt_log "support center: no answer / refused: ${resp:0:200}"; exit 0; }
gt_state centerReportAt "$(date -Is)"
# v10.38: the tickets' status + the center's last reply → the team leader sees them (support_tickets)
J -v r="$resp" >/dev/null <<'SQL'
insert into plant_state (key, value)
select 'supportTickets', coalesce(nullif(:'r', '')::jsonb -> 'tickets', '[]'::jsonb)::text
on conflict (key) do update set value = excluded.value, updated_at = now();
SQL

done_cmd(){ printf '%s' "{\"p_code\":\"$GT_PLANT_CODE\",\"p_secret\":\"$GT_PLANT_SECRET\",\"p_id\":$1,\"p_result\":\"$2\"}" | RPC sc_command_done >/dev/null; }
working(){ [ "$(J -c "select exists (select 1 from animals_pilot where updated_at > now() - interval '10 minutes')")" = "t" ]; }

# the release: install when it is new (the app at once — tablets ask / wait themselves; a server part only when nobody works)
install_release(){   # $1 = force (update_now)
  local rel; rel="$(J -v r="$resp" <<'SQL'
select concat_ws(' ', r ->> 'version', r ->> 'appUrl', r ->> 'appSha256', coalesce(r ->> 'sqlUrl', '-'), coalesce(r ->> 'sqlSha256', '-'))
  from (select nullif(:'r', '')::jsonb -> 'release' as r) x where x.r is not null and x.r <> 'null'::jsonb;
SQL
)"
  [ -n "$rel" ] || return 0
  read -r V AURL ASHA SURL SSHA <<<"$rel"
  local cur; cur="$(J -c "select value from plant_state where key = 'appVersion'")"
  [ "$V" = "$cur" ] && [ "$1" != "force" ] && return 0
  if [ "$SURL" != "-" ] && working && [ "$1" != "force" ]; then gt_log "release $V has a server part — waits until nobody works"; return 0; fi
  local T; T="$(mktemp -d)"
  curl -fsS -m 120 -o "$T/app.html" "$AURL" && [ "$(sha256sum "$T/app.html" | cut -d' ' -f1)" = "$ASHA" ] \
    || { gt_log "release $V: the app file did not download or its sha256 is wrong — not installed"; gt_state lastUpdateError "download/sha256 $V"; rm -rf "$T"; return 1; }
  if [ "$SURL" != "-" ]; then
    curl -fsS -m 120 -o "$T/02.sql" "$SURL" && [ "$(sha256sum "$T/02.sql" | cut -d' ' -f1)" = "$SSHA" ] \
      || { gt_log "release $V: the server file did not download or its sha256 is wrong — not installed"; gt_state lastUpdateError "download/sha256 $V"; rm -rf "$T"; return 1; }
    bash "$D/update-app.sh" "$T/app.html" "$T/02.sql"; rc=$?
  else bash "$D/update-app.sh" "$T/app.html"; rc=$?; fi
  rm -rf "$T"
  [ $rc -eq 0 ] && gt_state_del lastUpdateError || gt_state lastUpdateError "update-app.sh exit $rc ($V)"
  return $rc
}

# the support center's commands (only these four)
while read -r id cmd; do
  [ -n "$id" ] || continue
  case "$cmd" in
    restart_standby)   if [ -n "${GT_STANDBY_RESTART_CMD:-}" ]; then eval "$GT_STANDBY_RESTART_CMD" >/dev/null 2>&1 && done_cmd "$id" "restarted" || done_cmd "$id" "failed"; else done_cmd "$id" "GT_STANDBY_RESTART_CMD not set"; fi ;;
    reload_tablets)    J -c "update settings_pilot set settings = settings || jsonb_build_object('forceReloadAt', now()::text), updated_at = now(), device_id = 'server' where id = 1" >/dev/null && done_cmd "$id" "sent (tablets update when not in use)" ;;
    run_nightly_check) bash "$D/nightly-check.sh" >/dev/null 2>&1; done_cmd "$id" "ran" ;;
    update_now)        install_release force && done_cmd "$id" "installed" || done_cmd "$id" "failed — see the plant log" ;;
  esac
done < <(J -v r="$resp" <<'SQL'
select (c ->> 'id') || ' ' || (c ->> 'cmd') from jsonb_array_elements(coalesce(nullif(:'r', '')::jsonb -> 'commands', '[]'::jsonb)) c;
SQL
)
install_release
exit 0
