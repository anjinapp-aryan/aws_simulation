#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "$(date '+%H:%M:%S') [inject] adding 800ms latency toxic to the consumer's DB path"
curl -s -X POST http://localhost:59474/proxies/db/toxics \
  -H 'Content-Type: application/json' \
  -d '{"name":"latency","type":"latency","attributes":{"latency":800,"jitter":100}}'
echo ""
echo "$(date '+%H:%M:%S') [inject] publishing 60 normal orders as fast as possible (outpaces the now-slow consumer)"
for i in $(seq 1 60); do
  MSYS_NO_PATHCONV=1 docker compose run --rm producer "order-$i" normal >/dev/null 2>&1 &
done
wait
echo "$(date '+%H:%M:%S') [inject] all 60 published."
