#!/usr/bin/env bash
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
ORDER_ID="${1:-order-1}"
echo "--- order status ---"
curl -s "http://localhost:55000/order-status?id=${ORDER_ID}" | python -m json.tool
echo "--- connector status ---"
curl -s http://localhost:55083/connectors/order-outbox-connector/status | python -m json.tool
curl -s http://localhost:55083/connectors/payment-outbox-connector/status | python -m json.tool
