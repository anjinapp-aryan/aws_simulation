#!/usr/bin/env bash
# R4-03: real connection-pool exhaustion using pgbench (ships with the
# official postgres image - reused, not custom). PgBouncer's real
# max_client_conn=5 (pgbouncer.ini) is the thing actually enforcing the
# limit; pgbench just generates real concurrent connections against it,
# running a trivial custom script (no pgbench_accounts table needed).
set -uo pipefail
cd "$(dirname "$0")/.."
N="${1:-20}"
echo "$(date '+%H:%M:%S') opening $N concurrent connections through PgBouncer (max_client_conn=5)..."
docker compose exec -T postgres sh -c '
  echo "SELECT pg_sleep(0.2);" > /tmp/q.sql
  PGPASSWORD=apppass pgbench -h pgbouncer -p 6432 -U appuser -d appdb \
    -c '"$N"' -j 4 -T 5 -f /tmp/q.sql --no-vacuum
' 2>&1
