#!/bin/bash
# shared helpers for the GlattTrack plant-server tools (sourced, run as root or postgres)
set -euo pipefail
GT_CONF="${GT_CONF:-/etc/glatttrack/gt-plant.conf}"
[ -f "$GT_CONF" ] || { echo "missing $GT_CONF" >&2; exit 2; }
# shellcheck disable=SC1090
. "$GT_CONF"
GT_PGHOST="${GT_PGHOST:-/var/run/postgresql}"
gt_log(){ echo "$(date '+%F %T') [$(basename "$0")] $*" | tee -a "${GT_LOG:-/dev/null}" >&2; }
# psql on THIS server as the database superuser (local socket)
gt_psql(){ "${GT_PSQL:-psql}" -X -v ON_ERROR_STOP=1 -q -t -A -h "$GT_PGHOST" -p "$GT_PG_PORT" -U "${GT_PGUSER:-postgres}" -d "$GT_DB" "$@"; }
# psql on the OTHER server (by its own address) as the replication user — only to ask what it is
gt_peer_role(){
  PGPASSWORD="$GT_REPL_PASS" PGCONNECT_TIMEOUT=3 "${GT_PSQL:-psql}" -X -q -t -A -h "$GT_PEER_IP" -p "${GT_PEER_PORT:-$GT_PG_PORT}" \
    -U "$GT_REPL_USER" -d "$GT_DB" -c "select case when pg_is_in_recovery() then 'standby' else 'primary' end" 2>/dev/null || echo "down"
}
# timeline: goes up by one on every takeover — the server with the higher one is the true main server
GT_TLI_SQL="select case when pg_is_in_recovery() then 0 else ('x'||substr(pg_walfile_name(pg_current_wal_lsn()),1,8))::bit(32)::int end"
gt_peer_tli(){
  PGPASSWORD="$GT_REPL_PASS" PGCONNECT_TIMEOUT=3 "${GT_PSQL:-psql}" -X -q -t -A -h "$GT_PEER_IP" -p "${GT_PEER_PORT:-$GT_PG_PORT}" \
    -U "$GT_REPL_USER" -d "$GT_DB" -c "$GT_TLI_SQL" 2>/dev/null || echo 0
}
gt_self_tli(){ gt_psql -c "$GT_TLI_SQL" 2>/dev/null || echo 0; }
# can this server see the plant network? (a server cut off from everything must not take over)
gt_net_ok(){ [ -z "${GT_GATEWAY_IP:-}" ] && return 0; ping -c 2 -W 1 "$GT_GATEWAY_IP" >/dev/null 2>&1; }
gt_pg_stop(){ eval "${GT_STOP_CMD:-systemctl stop postgresql}"; }
gt_pg_start(){ eval "${GT_START_CMD:-systemctl start postgresql}"; }
gt_self_role(){ gt_psql -c "select case when pg_is_in_recovery() then 'standby' else 'primary' end" 2>/dev/null || echo "down"; }
# write a plant_state key (on the primary only — a standby is read-only)
gt_state(){ gt_psql -c "insert into plant_state (key, value) values ('$1', \$v\$$2\$v\$) on conflict (key) do update set value = excluded.value, updated_at = now()"; }
gt_state_del(){ gt_psql -c "delete from plant_state where key = '$1'"; }
