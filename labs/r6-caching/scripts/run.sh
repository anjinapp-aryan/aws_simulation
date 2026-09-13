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

echo "waiting for valkey-primary to accept connections..."
until docker compose exec -T valkey-primary valkey-cli ping 2>/dev/null | grep -q PONG; do
  sleep 1
done
echo "valkey-primary ready"

echo "creating real Toxiproxy proxy (valkey) via control API"
curl -s -X POST http://localhost:61474/proxies \
  -d '{"name":"valkey","listen":"0.0.0.0:6379","upstream":"valkey-primary:6379","enabled":true}' \
  -H "Content-Type: application/json" | python -m json.tool

echo ""
echo "R6 stack up."
echo "Traefik dashboard : http://localhost:61081"
echo "App (via Traefik)  : http://localhost:61080"
echo "Grafana            : http://localhost:61300"
echo "Prometheus         : http://localhost:61090"
echo "redis-commander    : http://localhost:61082"
echo "Dozzle             : http://localhost:61888"
