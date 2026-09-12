#!/usr/bin/env bash
# R5-05: reuse R4's Toxiproxy latency/cut mechanism unchanged.
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
MODE="${1:-latency}"   # latency | severe | cut

case "$MODE" in
  latency)
    echo "$(date '+%H:%M:%S') injecting 300ms DB latency"
    curl -s -X POST http://localhost:58474/proxies/postgres/toxics \
      -d '{"name":"latency","type":"latency","attributes":{"latency":300,"jitter":50}}' \
      -H "Content-Type: application/json"
    ;;
  severe)
    echo "$(date '+%H:%M:%S') escalating to 2000ms DB latency"
    curl -s -X DELETE http://localhost:58474/proxies/postgres/toxics/latency >/dev/null || true
    curl -s -X POST http://localhost:58474/proxies/postgres/toxics \
      -d '{"name":"latency","type":"latency","attributes":{"latency":2000,"jitter":100}}' \
      -H "Content-Type: application/json"
    ;;
  cut)
    echo "$(date '+%H:%M:%S') cutting DB connectivity (disabling proxy)"
    curl -s -X POST http://localhost:58474/proxies/postgres -d '{"enabled":false}' \
      -H "Content-Type: application/json"
    ;;
  *)
    echo "usage: break-db.sh latency|severe|cut"; exit 1 ;;
esac
echo ""
