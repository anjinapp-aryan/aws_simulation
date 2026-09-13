#!/usr/bin/env bash
# R6-03/R6-04: reuse the exact Toxiproxy mechanism proven in R4/R5,
# retargeted at the cache instead of the database.
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
MODE="${1:-cut}"   # cut | latency

case "$MODE" in
  cut)
    echo "$(date '+%H:%M:%S') cutting cache connectivity (disabling proxy)"
    curl -s -X POST http://localhost:61474/proxies/valkey -d '{"enabled":false}' \
      -H "Content-Type: application/json"
    ;;
  latency)
    echo "$(date '+%H:%M:%S') injecting 500ms cache latency"
    curl -s -X POST http://localhost:61474/proxies/valkey/toxics \
      -d '{"name":"latency","type":"latency","attributes":{"latency":500,"jitter":50}}' \
      -H "Content-Type: application/json"
    ;;
  *)
    echo "usage: break-cache.sh cut|latency"; exit 1 ;;
esac
echo ""
