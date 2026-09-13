#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
echo "--- app /health ---"
curl -s -w " (HTTP %{http_code})\n" http://localhost:61080/health
echo "--- app /cached-item?id=1 (x2, expect MISS then HIT) ---"
curl -s -w " (HTTP %{http_code})\n" "http://localhost:61080/cached-item?id=1"
curl -s -w " (HTTP %{http_code})\n" "http://localhost:61080/cached-item?id=1"
echo "--- sentinel master ---"
docker compose exec -T sentinel valkey-cli -p 26379 sentinel get-master-addr-by-name mymaster
