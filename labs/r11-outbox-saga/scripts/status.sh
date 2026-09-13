#!/usr/bin/env bash
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
echo "--- containers ---"
docker compose ps
echo ""
echo "--- connector status ---"
curl -s http://localhost:55083/connectors/order-outbox-connector/status | python -m json.tool
curl -s http://localhost:55083/connectors/payment-outbox-connector/status | python -m json.tool
echo ""
echo "--- toxiproxy ---"
curl -s http://localhost:55474/proxies | python -m json.tool
