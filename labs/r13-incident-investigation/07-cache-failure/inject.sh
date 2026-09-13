#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "$(date '+%H:%M:%S') [inject] tightening valkey-primary maxmemory + eviction policy (real Valkey config, real eviction)"
docker compose exec -T valkey-primary valkey-cli CONFIG SET maxmemory 1mb
docker compose exec -T valkey-primary valkey-cli CONFIG SET maxmemory-policy allkeys-lru
echo "$(date '+%H:%M:%S') [inject] generating traffic against many distinct keys (200 distinct items, repeated 3x each) to force eviction of previously-cached hot keys"
> evidence/hit-miss.txt
for round in 1 2 3; do
  for i in $(seq 1 200); do
    curl -s "http://localhost:60080/cached-item?id=$i" >> evidence/hit-miss.txt
    echo "" >> evidence/hit-miss.txt
  done
done
echo "$(date '+%H:%M:%S') [inject] done."
