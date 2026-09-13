#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
docker compose up -d --build
echo "waiting for postgres healthy..."
until [ "$(docker inspect -f '{{.State.Health.Status}}' $(docker compose ps -q postgres) 2>/dev/null)" = "healthy" ]; do
  sleep 1
done
echo "creating real Toxiproxy proxy (db) via control API"
curl -s -X POST http://localhost:64474/proxies -d '{"name":"db","listen":"0.0.0.0:6432","upstream":"pgbouncer:6432","enabled":true}' -H "Content-Type: application/json"
echo ""
echo "waiting for Envoy..."
until curl -sf http://localhost:64901/ready >/dev/null 2>&1; do sleep 1; done
echo ""
echo "R9 stack up."
echo "Envoy (protected via Envoy)  : http://localhost:64080/order-raw?id=1"
echo "Envoy admin                  : http://localhost:64901/clusters"
echo "App direct (app-breaker)     : http://localhost:64000/order?id=1"
echo "Breaker status               : http://localhost:64000/breaker-status"
echo "Grafana                      : http://localhost:64300"
echo "Prometheus                   : http://localhost:64090"
echo "Dozzle                       : http://localhost:64888"
