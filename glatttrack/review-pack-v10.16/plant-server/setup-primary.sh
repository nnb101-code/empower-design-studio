#!/bin/bash
# Run ONCE on the main server (A), as root, after GlattTrack is installed and working.
# Prepares it to send every change to the standby server, without losing data:
# a ruling is confirmed to a tablet only after the standby has it too
# (when the standby is down, gt-sync-watchdog lets the main server work alone).
. "$(dirname "$0")/gt-lib.sh"
gt_check_secrets
gt_log "preparing $GT_SELF ($GT_SELF_IP) as the main server; standby at $GT_PEER_IP"
gt_psql <<SQL
do \$\$ begin
  if not exists (select 1 from pg_roles where rolname = '$GT_REPL_USER') then
    create role $GT_REPL_USER with replication login password '$GT_REPL_PASS';
  else
    alter role $GT_REPL_USER with replication login password '$GT_REPL_PASS';
  end if;
end \$\$;
grant connect on database $GT_DB to $GT_REPL_USER;
alter system set wal_level = 'replica';
alter system set max_wal_senders = 5;
alter system set wal_keep_size = '2GB';
alter system set hot_standby = 'on';
alter system set wal_log_hints = 'on';
alter system set synchronous_commit = 'on';
alter system set synchronous_standby_names = 'ANY 1 ($GT_STANDBY_APP)';
SQL
# this server's own name (A/B) — in its own config file, so the standby keeps its own name
CONF="$(gt_psql -c 'show config_file')"
sed -i '/^gt\.server_name/d' "$CONF"
echo "gt.server_name = '$GT_SELF'" >> "$CONF"
# the standby (and this server, once it is the standby) may connect for replication
HBA="$(gt_psql -c 'show hba_file')"
for ip in "$GT_PEER_IP" "$GT_SELF_IP"; do
  line="host replication $GT_REPL_USER $ip/32 scram-sha-256"
  grep -qxF "$line" "$HBA" || echo "$line" >> "$HBA"
  line="host $GT_DB $GT_REPL_USER $ip/32 scram-sha-256"
  grep -qxF "$line" "$HBA" || echo "$line" >> "$HBA"
done
gt_state standbyExpected 1
gt_state plantServer on
gt_log "done. Restart Postgres once (wal_level changed): systemctl restart postgresql"
