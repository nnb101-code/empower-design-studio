#!/bin/bash
# Runs a Postgres tool (psql / pg_dump / pg_restore) as the database's own system user when called by root.
# (full review P1) Ubuntu / Debian's Postgres lets the "postgres" database user in over the local socket only
# for the "postgres" system user (peer authentication) — root running "psql -U postgres" is refused.
if [ "$(id -u)" = "0" ] && [ "${GT_PGUSER:-postgres}" = "postgres" ] && [ -z "${GT_NO_RUNAS:-}" ] && command -v runuser >/dev/null 2>&1 \
   && id postgres >/dev/null 2>&1; then
  cd / 2>/dev/null || true                     # the postgres user may not read root's folder
  exec runuser -u postgres -- "$@"
fi
exec "$@"
