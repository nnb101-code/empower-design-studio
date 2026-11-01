#!/bin/bash
# keepalived health check: ONLY the main server may hold the floating address (review A3).
# A backup server (in recovery), a fenced old main server, or one whose Postgres does not answer
# never holds it — so the tablets can never reach two servers that both accept rulings.
GT_CONF="${GT_CONF:-/etc/glatttrack/gt-plant.conf}"; . "$GT_CONF"
[ -f /var/lib/glatttrack/needs-rejoin ] && exit 1
# (full review P1) as the database's own system user (keepalived runs this as root; Ubuntu's peer authentication)
r="$("$(cd "$(dirname "$0")/.." && pwd)/gt-psql.sh" -X -q -t -A -h "${GT_PGHOST:-/var/run/postgresql}" -p "$GT_PG_PORT" -U postgres -d "$GT_DB" -c "select pg_is_in_recovery()" 2>/dev/null)"
[ "$r" = "f" ]
