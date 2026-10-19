#!/bin/bash
# shared helpers for the GlattTrack plant-server tools (sourced, run as root or postgres)
set -euo pipefail
GT_CONF="${GT_CONF:-/etc/glatttrack/gt-plant.conf}"
[ -f "$GT_CONF" ] || { echo "missing $GT_CONF" >&2; exit 2; }
# (audit) root runs the settings file and these scripts as code: they (and their folders) must belong to root and
# nobody else may change them — otherwise another user could run commands as root
gt_owner_ok(){ local f u a; for f in "$@"; do
  read -r u a < <(stat -c '%u %a' "$f" 2>/dev/null) || { echo "ERROR: cannot check $f" >&2; return 1; }
  [ "$u" = "0" ] && [ $(( 8#$a & 8#022 )) -eq 0 ] || { echo "ERROR: $f must belong to root and be writable only by root (now: user $u, mode $a)" >&2; return 1; }
done; }
if [ "$(id -u)" = "0" ]; then
  _gt_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  gt_owner_ok "$GT_CONF" "$(dirname "$GT_CONF")" "$_gt_dir" $(compgen -G "$_gt_dir/*.sh") $(compgen -G "$_gt_dir/*.py") || exit 2
fi
# shellcheck disable=SC1090
. "$GT_CONF"
GT_PGHOST="${GT_PGHOST:-/var/run/postgresql}"
GT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# (full review P1) root → the Postgres tools run as the "postgres" system user (Ubuntu / Debian peer authentication)
GT_PSQL="${GT_PSQL:-$GT_LIB_DIR/gt-psql.sh}"
GT_ASPG="${GT_ASPG:-$GT_LIB_DIR/gt-as-pg.sh}"
umask 077
# the settings file holds passwords: readable by root only
[ "$(id -u)" = "0" ] && chmod 600 "$GT_CONF" 2>/dev/null || true
# refuse to run with an empty, sample or short password (review A6)
gt_check_secrets(){
  case "${GT_REPL_PASS:-}" in ""|change-me*|*CHANGE*) echo "ERROR: set GT_REPL_PASS in $GT_CONF (openssl rand -hex 24)" >&2; exit 2;; esac
  [ "${#GT_REPL_PASS}" -ge 16 ] || { echo "ERROR: GT_REPL_PASS must be at least 16 characters" >&2; exit 2; }
  case "${GT_VRRP_PASS:-}" in ""|gtplant1|change-me*|*CHANGE*) echo "ERROR: set GT_VRRP_PASS in $GT_CONF (8 random characters)" >&2; exit 2;; esac
}
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
# (full review P6) the key and the value go in as psql variables — any text is safe
gt_state(){ gt_psql -v k="$1" -v v="$2" <<'SQL'
insert into plant_state (key, value) values (:'k', :'v') on conflict (key) do update set value = excluded.value, updated_at = now();
SQL
}
gt_state_del(){ gt_psql -v k="$1" <<'SQL'
delete from plant_state where key = :'k';
SQL
}
# (round-2 review P-up1) is this release signed by the manufacturer? $1 = the signed text, $2 = the signature (base64).
# The manufacturer's public key: GT_RELEASE_PUBKEY (default /etc/glatttrack/release-public.pem). No key = no update.
gt_release_verify(){
  # (audit) a key change: the manufacturer's NEXT public key may sit beside the current one for a while
  # (GT_RELEASE_PUBKEY_NEXT); a release signed with either is installed — see PLANT-RESILIENCE-HE.md
  local key="${GT_RELEASE_PUBKEY:-/etc/glatttrack/release-public.pem}" next="${GT_RELEASE_PUBKEY_NEXT:-}" t rc=1 k
  [ -f "$key" ] || [ -n "$next" -a -f "$next" ] || { gt_log "release: no manufacturer key ($key) — updates are not installed"; return 1; }
  [ -n "$1" ] && [[ "$2" =~ ^[A-Za-z0-9+/]{86}==$ ]] || return 1
  t="$(mktemp -d)"
  printf '%s' "$1" > "$t/m"; printf '%s' "$2" | base64 -d > "$t/s" 2>/dev/null
  for k in "$key" "$next"; do
    [ -n "$k" ] && [ -f "$k" ] || continue
    openssl pkeyutl -verify -pubin -inkey "$k" -rawin -in "$t/m" -sigfile "$t/s" >/dev/null 2>&1 && { rc=0; break; }
  done
  rm -rf "$t"; return $rc
}
