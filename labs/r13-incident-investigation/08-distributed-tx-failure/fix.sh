#!/usr/bin/env bash
set -euo pipefail
echo "$(date '+%H:%M:%S') [fix] resuming order-outbox-connector"
curl -s -X PUT http://localhost:53083/connectors/order-outbox-connector/resume
echo ""
sleep 3
curl -s http://localhost:53083/connectors/order-outbox-connector/status
echo ""
echo "$(date '+%H:%M:%S') [fix] waiting for the 3 previously-stuck orders to drain (no data loss - Debezium replays from its paused WAL position)"
sleep 8
for i in 1 2 3; do
  curl -s "http://localhost:53000/order-status?id=order-stuck$i" -w "\n"
done
