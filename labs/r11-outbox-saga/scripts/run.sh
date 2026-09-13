#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
docker compose up -d --build

echo "waiting for order-db and payment-db healthy..."
until [ "$(docker inspect -f '{{.State.Health.Status}}' $(docker compose ps -q order-db) 2>/dev/null)" = "healthy" ] && \
      [ "$(docker inspect -f '{{.State.Health.Status}}' $(docker compose ps -q payment-db) 2>/dev/null)" = "healthy" ]; do
  sleep 1
done
echo "both databases healthy"

echo "creating real Toxiproxy proxy (kafka) via control API - fronts Debezium's Kafka publish path"
curl -s -X POST http://localhost:55474/proxies -d '{"name":"kafka","listen":"0.0.0.0:19092","upstream":"kafka:9092","enabled":true}' -H "Content-Type: application/json"
echo ""

echo "waiting for Kafka Connect (Debezium) REST API..."
until curl -sf http://localhost:55083/connectors >/dev/null 2>&1; do sleep 2; done
echo "Debezium Connect ready"

echo "registering real Debezium connectors (EventRouter outbox SMT)..."
curl -s -X POST -H "Content-Type: application/json" http://localhost:55083/connectors -d @debezium/order-connector.json
echo ""
curl -s -X POST -H "Content-Type: application/json" http://localhost:55083/connectors -d @debezium/payment-connector.json
echo ""

sleep 3
echo "--- connector status ---"
curl -s http://localhost:55083/connectors/order-outbox-connector/status | python -m json.tool
curl -s http://localhost:55083/connectors/payment-outbox-connector/status | python -m json.tool

echo ""
echo "R11 stack up."
echo "Order Service     : http://localhost:55000/place-order?id=order-1&fail_payment=0"
echo "Kafka UI          : http://localhost:55080"
echo "pgweb (order-db)  : http://localhost:55081"
echo "pgweb (payment-db): http://localhost:55082"
echo "Debezium Connect  : http://localhost:55083/connectors"
