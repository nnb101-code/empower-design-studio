#!/bin/bash
# local test of the plant-server kit v10.16: A=5441 B=5442
D=/home/user/empower-design-studio/glatttrack/plant-server; T=$(dirname "$0"); BIN=/usr/lib/postgresql/16/bin
q(){ psql -h /tmp -p $1 -U postgres -d gtapp -Atc "$2" 2>&1; }
TOK=$(q 5441 "select manager_login('e2e-tl-code-7731')->>'token'")
H(){ q $1 "select (system_health('$TOK')->'attention')::text || ' info=' || (system_health('$TOK')->'info')::text"; }
VIP(){ GT_CONF=$T/$1.conf GT_PGHOST=/tmp $D/keepalived/check_pg.sh && echo "$1 may hold the address: YES" || echo "$1 may hold the address: no"; }
start(){ eval "$(grep ^GT_START_CMD $T/$1.conf | sed 's/^GT_START_CMD=/c=/')"; eval "$c" >/dev/null; sleep 2; }
step(){ echo; echo "=== $*"; }
step "0 no password in the settings → refused"; GT_CONF=$T/Anopass.conf $D/setup-primary.sh 2>&1 | tail -1
step "1 healthy: only the main server holds the address"; VIP A; VIP B
step "2 A↔B cut, both see the plant (split-brain case): B does NOT take over"
GT_CONF=$T/Bcut.conf $D/promote.sh 2>&1 | tail -1; echo "B role: $(q 5442 'select case when pg_is_in_recovery() then $$standby$$ else $$primary$$ end')"; VIP B
step "3 strict mode: B gone → a ruling waits (no ruling on one server only)"
su postgres -c "$BIN/pg_ctl -D /var/tmp/gtB stop -m immediate" >/dev/null
( GT_CONF=$T/A.conf GT_SYNC_MODE=strict GT_SYNC_GRACE=2 GT_SYNC_STEP=1 timeout 8 $D/gt-sync-watchdog.sh 2>/dev/null ) &
t0=$(date +%s); timeout 7 psql -h /tmp -p 5441 -U postgres -d gtapp -Atc "update plant_state set value='strict' where key='schemaStep' and false" >/dev/null 2>&1
timeout 7 psql -h /tmp -p 5441 -U postgres -d gtapp -Atc "insert into plant_state(key,value) values('haStrict','x') on conflict(key) do update set value='x'" >/dev/null 2>&1; rc=$?
wait; echo "write with B gone (strict): $([ $rc = 124 ] && echo 'WAITED (not confirmed)' || echo "returned rc=$rc") after $(( $(date +%s)-t0 ))s; sync=[$(q 5441 'show synchronous_standby_names')]"
start B; sleep 3; echo "B back → the waiting write: $(q 5442 "select coalesce((select value from plant_state where key='haStrict'),'missing')")"
step "4 available mode: B gone → A goes on alone after ~3 s"
su postgres -c "$BIN/pg_ctl -D /var/tmp/gtB stop -m immediate" >/dev/null
( GT_CONF=$T/A.conf GT_SYNC_GRACE=3 GT_SYNC_STEP=1 timeout 9 $D/gt-sync-watchdog.sh 2>/dev/null ) &
t0=$(date +%s); timeout 15 psql -h /tmp -p 5441 -U postgres -d gtapp -Atc "insert into plant_state(key,value) values('haAvail','y') on conflict(key) do update set value='y' returning 'write confirmed'"; echo "after $(( $(date +%s)-t0 ))s"; wait; H 5441
start B; GT_CONF=$T/A.conf GT_ONCE=1 $D/gt-sync-watchdog.sh 2>&1 | tail -1
step "5 A dies; nobody confirmed → B stays the backup, nobody holds the address (tablets stop)"
su postgres -c "$BIN/pg_ctl -D /var/tmp/gtA stop -m immediate" >/dev/null
GT_CONF=$T/B.conf $D/promote.sh 2>&1 | tail -1; VIP A; VIP B
step "6 a person confirms A is off → takeover"
echo OFF | GT_CONF=$T/B.conf $D/takeover.sh 2>&1 | tail -1; VIP B; H 5442
step "7 old A starts as main → fenced, never holds the address"
start A; GT_CONF=$T/A.conf GT_ONCE=1 $D/gt-sync-watchdog.sh 2>&1 | tail -1; VIP A
step "8 A rejoins as backup"; GT_CONF=$T/A.conf $D/rejoin-as-standby.sh --yes 2>&1 | tail -1; GT_CONF=$T/B.conf GT_ONCE=1 $D/gt-sync-watchdog.sh 2>&1 | tail -1; VIP A; VIP B
step "9 backup checked by a full restore"; GT_CONF=$T/B.conf $D/backup.sh 2>&1 | tail -1
step "10 a backup whose event chain is broken → FAILED, not green"
q 5442 "alter table events_pilot disable trigger user; update events_pilot set payload = payload || '{\"x\":1}'::jsonb where chain_pos = (select min(chain_pos) from events_pilot where chain_pos is not null); alter table events_pilot enable trigger user" >/dev/null
GT_CONF=$T/B.conf $D/backup.sh 2>&1 | tail -1; q 5442 "select system_health('$TOK')->'backup'"
