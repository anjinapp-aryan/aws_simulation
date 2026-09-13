#!/usr/bin/env bash
# R6-06: real Valkey primary failure + real Sentinel election.
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
echo "$(date '+%H:%M:%S') killing valkey-primary container"
docker kill $(docker compose ps -q valkey-primary)
echo "watching Sentinel's view of the master for up to 20s..."
for i in $(seq 1 10); do
  RESULT=$(docker compose exec -T sentinel valkey-cli -p 26379 sentinel get-master-addr-by-name mymaster 2>&1 || echo "sentinel query failed")
  echo "$(date '+%H:%M:%S') sentinel master-addr: $RESULT"
  sleep 2
done
