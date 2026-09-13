#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
echo "$(date '+%H:%M:%S') removing cache latency toxic (if any)"
curl -s -X DELETE http://localhost:61474/proxies/valkey/toxics/latency >/dev/null || true
echo "$(date '+%H:%M:%S') re-enabling cache proxy (if cut)"
curl -s -X POST http://localhost:61474/proxies/valkey -d '{"enabled":true}' \
  -H "Content-Type: application/json" >/dev/null
echo "fix applied"
