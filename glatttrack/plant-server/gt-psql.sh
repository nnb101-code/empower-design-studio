#!/bin/bash
# psql as the database's own system user when called by root (see gt-as-pg.sh)
exec "$(dirname "$0")/gt-as-pg.sh" psql "$@"
