#!/bin/bash
# keepalived health check: this server may hold the floating address only while its
# Postgres answers. (Which server is the MAIN one is decided by promote.sh.)
GT_CONF="${GT_CONF:-/etc/glatttrack/gt-plant.conf}"; . "$GT_CONF"
[ -f /var/lib/glatttrack/needs-rejoin ] && exit 1
psql -X -q -t -A -h "${GT_PGHOST:-/var/run/postgresql}" -p "$GT_PG_PORT" -U postgres -d "$GT_DB" -c "select 1" >/dev/null 2>&1
