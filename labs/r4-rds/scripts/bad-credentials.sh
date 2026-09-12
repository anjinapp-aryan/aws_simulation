#!/usr/bin/env bash
# R4-02: real wrong password against real Postgres/PgBouncer auth enforcement.
#
# First attempt used a one-off `docker run` with an inline multi-line Python
# heredoc, which hung indefinitely under Git Bash (the multi-line quoting
# didn't survive). Investigated by isolating the test onto the ALREADY
# RUNNING app container instead - confirmed the real auth rejection is
# instant (0.00s), so the hang was a script-quoting bug, not a system
# defect. Fixed by using `docker compose exec` against the running
# container, matching what was proven to work.
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
echo "$(date '+%H:%M:%S') querying with a deliberately wrong password"
docker compose exec -T app python3 -c "
import psycopg2, time
start = time.time()
try:
    psycopg2.connect(host='toxiproxy', port=5432, dbname='appdb', user='appuser', password='WRONG_PASSWORD', connect_timeout=3)
    print('UNEXPECTED: connected with wrong password')
except Exception as e:
    print(f'EXPECTED real auth failure after {time.time()-start:.2f}s: {type(e).__name__}: {e}')
"
