#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "$(date '+%H:%M:%S') [inject] pausing the order-outbox-connector via the real Kafka Connect REST API (not a crash - a genuine PAUSED state)"
curl -s -X PUT http://localhost:53083/connectors/order-outbox-connector/pause
echo ""
sleep 2
curl -s http://localhost:53083/connectors/order-outbox-connector/status
echo ""
echo "$(date '+%H:%M:%S') [inject] placing 3 orders while the connector is paused"
for i in 1 2 3; do
  curl -s "http://localhost:53000/place-order?id=order-stuck$i&fail_payment=0" -w "\n" >> evidence/orders-placed.txt
done
echo "$(date '+%H:%M:%S') [inject] waiting 15s, then checking order-status (should still be CREATED)"
sleep 15
for i in 1 2 3; do
  curl -s "http://localhost:53000/order-status?id=order-stuck$i" -w "\n" >> evidence/status-after-15s.txt
done
cat evidence/status-after-15s.txt
