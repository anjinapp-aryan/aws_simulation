#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1

echo "--- starting stack ---"
docker compose up -d --build

echo "--- waiting for postgres healthy ---"
for i in $(seq 1 30); do
  docker compose ps postgres 2>&1 | grep -q "healthy" && break
  sleep 1
done

echo "--- creating the real Toxiproxy proxy (app -> toxiproxy:5432 -> pgbouncer:6432) ---"
sleep 2
curl -s -X POST http://localhost:48474/proxies \
  -H 'Content-Type: application/json' \
  -d '{"name":"postgres","listen":"0.0.0.0:5432","upstream":"pgbouncer:6432","enabled":true}'
echo ""

echo ""
echo "app:         http://localhost:48000/db"
echo "Toxiproxy API: http://localhost:48474/proxies"
echo "Prometheus:  http://localhost:49090"
echo "Grafana:     http://localhost:43000  (anonymous admin access)"
echo "pgweb:       http://localhost:48081"
echo ""
bash scripts/status.sh
