#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
docker compose up -d --build
echo "waiting for postgres healthy..."
until [ "$(docker inspect -f '{{.State.Health.Status}}' $(docker compose ps -q postgres) 2>/dev/null)" = "healthy" ]; do
  sleep 1
done
echo "waiting for jaeger..."
until curl -sf http://localhost:63686 >/dev/null 2>&1; do sleep 1; done
echo "creating real Toxiproxy proxies (db, cache) via control API"
curl -s -X POST http://localhost:63474/proxies -d '{"name":"db","listen":"0.0.0.0:6432","upstream":"pgbouncer:6432","enabled":true}' -H "Content-Type: application/json"
echo ""
curl -s -X POST http://localhost:63474/proxies -d '{"name":"cache","listen":"0.0.0.0:6379","upstream":"valkey:6379","enabled":true}' -H "Content-Type: application/json"
echo ""
echo ""
echo "R8 stack up."
echo "Jaeger UI     : http://localhost:63686"
echo "App           : http://localhost:63080/checkout?id=1"
echo "Traefik dash  : http://localhost:63081"
echo "RabbitMQ UI   : http://localhost:63672 (guest/guest)"
echo "Grafana       : http://localhost:63300"
echo "Prometheus    : http://localhost:63090"
echo "Dozzle        : http://localhost:63888"
