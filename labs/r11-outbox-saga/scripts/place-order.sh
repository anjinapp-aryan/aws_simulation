#!/usr/bin/env bash
# usage: place-order.sh <order-id> [fail_payment=0|1]
set -euo pipefail
cd "$(dirname "$0")/.."
ORDER_ID="${1:-order-$(date +%s)}"
FAIL="${2:-0}"
curl -s "http://localhost:55000/place-order?id=${ORDER_ID}&fail_payment=${FAIL}"
echo ""
