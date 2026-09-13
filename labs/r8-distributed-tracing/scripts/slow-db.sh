#!/usr/bin/env bash
# R8-02: inject real DB latency via Toxiproxy.
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
MODE="${1:-on}"
if [ "$MODE" = "on" ]; then
  curl -s -X POST http://localhost:63474/proxies/db/toxics \
    -d '{"name":"latency","type":"latency","attributes":{"latency":800,"jitter":50}}' \
    -H "Content-Type: application/json"
else
  curl -s -X DELETE http://localhost:63474/proxies/db/toxics/latency
fi
echo ""
