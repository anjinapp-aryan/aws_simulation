#!/usr/bin/env bash
set -euo pipefail
echo "$(date '+%H:%M:%S') [fix] removing latency toxic from order-service's DB path"
curl -s -X DELETE http://localhost:56474/proxies/orderdb/toxics/latency
echo ""
echo "$(date '+%H:%M:%S') [fix] verifying recovery: placing order-fix1"
curl -s "http://localhost:56000/place-order?id=order-fix1&fail_payment=0" -w "\n"
sleep 3
curl -s "http://localhost:56000/order-status?id=order-fix1"
