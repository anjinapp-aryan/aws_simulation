#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
mkdir -p data
docker compose up -d --build rabbitmq toxiproxy prometheus grafana dozzle
echo "waiting for RabbitMQ management API..."
until curl -sf -u guest:guest http://localhost:62672/api/overview >/dev/null 2>&1; do
  sleep 1
done
echo "RabbitMQ ready"

echo "creating real Toxiproxy proxy (rabbitmq) via control API"
curl -s -X POST http://localhost:62474/proxies \
  -d '{"name":"rabbitmq","listen":"0.0.0.0:5672","upstream":"rabbitmq:5672","enabled":true}' \
  -H "Content-Type: application/json" | python -m json.tool

echo "starting consumer"
docker compose up -d consumer

echo ""
echo "R7 stack up."
echo "RabbitMQ Management UI : http://localhost:62672 (guest/guest)"
echo "Grafana                : http://localhost:62300"
echo "Prometheus             : http://localhost:62090"
echo "Dozzle                 : http://localhost:62888"
