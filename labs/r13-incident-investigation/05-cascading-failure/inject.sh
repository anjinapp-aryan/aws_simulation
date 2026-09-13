#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "$(date '+%H:%M:%S') [inject] adding 800ms latency toxic to order-service's OWN DB path only (order-db proxy); Debezium's direct connection to order-db is untouched"
curl -s -X POST http://localhost:56474/proxies/orderdb/toxics \
  -H 'Content-Type: application/json' \
  -d '{"name":"latency","type":"latency","attributes":{"latency":800,"jitter":100}}'
echo ""
echo "$(date '+%H:%M:%S') [inject] placing order-fault1"
curl -s "http://localhost:56000/place-order?id=order-fault1&fail_payment=0" -w "\n"
echo "$(date '+%H:%M:%S') [inject] polling order-status and payment-db every 1s for 20s"
for i in $(seq 1 20); do
  T=$(date '+%H:%M:%S')
  OS=$(curl -s "http://localhost:56000/order-status?id=order-fault1")
  echo "$T order-status: $OS" >> evidence/poll.txt
  sleep 1
done
echo "$(date '+%H:%M:%S') [inject] done, see evidence/poll.txt"
