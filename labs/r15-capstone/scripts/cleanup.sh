#!/usr/bin/env bash
# R15 capstone - destructive teardown. This is the ONLY script that removes
# data (same convention as R11's cleanup.sh). run.sh never does this.
#
# By default tears down R15 only and leaves the R14 Patroni foundation up,
# because R14 is a standalone lab in its own right. Pass --all to tear down
# the R14 prerequisite too (what a true cold-start test needs).
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1

R14="../r14-ha-dr/patroni-src"

echo "tearing down R15..."
docker compose down -v

if [ "${1:-}" = "--all" ]; then
  echo "tearing down the R14 Patroni prerequisite..."
  docker compose -f "$R14/docker-compose.yml" down -v
  echo "R14 + R15 torn down."
else
  echo "R15 torn down. R14 Patroni foundation left running (use --all to remove it too)."
fi
echo "AWS spend: \$0."
