#!/bin/bash
# starts scanner-relay.py with the plant server's settings (gt-plant.conf); see scanner-relay.py
. "$(dirname "$0")/gt-lib.sh"
export GT_PSQL GT_PGHOST GT_PG_PORT GT_DB GT_PGUSER="${GT_PGUSER:-postgres}" GT_SCANNER_PORT="${GT_SCANNER_PORT:-9300}"
exec python3 "$(dirname "$0")/scanner-relay.py"
