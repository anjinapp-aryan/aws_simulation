#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
docker compose up -d --build
echo "waiting for postgres healthy..."
until [ "$(docker inspect -f '{{.State.Health.Status}}' $(docker compose ps -q postgres) 2>/dev/null)" = "healthy" ]; do
  sleep 1
done
echo "postgres healthy"

echo "creating real Toxiproxy proxy (postgres) via control API"
curl -s -X POST http://localhost:58474/proxies \
  -d '{"name":"postgres","listen":"0.0.0.0:5432","upstream":"pgbouncer:6432","enabled":true}' \
  -H "Content-Type: application/json" | python -m json.tool

echo "R5 stack up."
echo "Traefik dashboard : http://localhost:58081"
echo "App (via Traefik)  : http://localhost:58080"
echo "Grafana            : http://localhost:53000"
echo "Prometheus         : http://localhost:59090"
echo "cAdvisor           : http://localhost:58082"
echo "Dozzle             : http://localhost:58888"
