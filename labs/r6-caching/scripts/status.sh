#!/usr/bin/env bash
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
echo "--- containers ---"
docker compose ps
echo ""
echo "--- Toxiproxy proxy state ---"
curl -s http://localhost:61474/proxies | python -m json.tool
echo ""
echo "--- app /health ---"
curl -s -w " (HTTP %{http_code})\n" http://localhost:61080/health
echo ""
echo "--- valkey replication state ---"
docker compose exec -T valkey-primary valkey-cli info replication | grep -E "role|connected_slaves|slave0"
echo ""
echo "--- sentinel view of master ---"
docker compose exec -T sentinel valkey-cli -p 26379 sentinel get-master-addr-by-name mymaster
