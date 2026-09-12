#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
echo "$(date '+%H:%M:%S') removing app unhealthy flag"
docker compose exec -T app rm -f /tmp/unhealthy || true
echo "$(date '+%H:%M:%S') removing DB latency toxic (if any)"
curl -s -X DELETE http://localhost:58474/proxies/postgres/toxics/latency >/dev/null || true
echo "$(date '+%H:%M:%S') re-enabling DB proxy (if cut)"
curl -s -X POST http://localhost:58474/proxies/postgres -d '{"enabled":true}' \
  -H "Content-Type: application/json" >/dev/null
echo "fix applied"
