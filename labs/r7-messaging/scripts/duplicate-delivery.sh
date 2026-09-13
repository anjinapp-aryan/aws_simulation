#!/usr/bin/env bash
# R7-05: usage: duplicate-delivery.sh <with|without> <order-id>
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-without}"
ORDER_ID="${2:-dup-$(date +%s)}"
if [ "$MODE" = "with" ]; then
  ./scripts/produce.sh "$ORDER_ID" crash_idempotent
else
  ./scripts/produce.sh "$ORDER_ID" crash
fi
