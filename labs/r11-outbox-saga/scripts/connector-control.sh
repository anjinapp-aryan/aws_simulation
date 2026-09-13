#!/usr/bin/env bash
# R11-06: real Kafka Connect connector lifecycle control (pause/resume).
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
ACTION="${1:-pause}"   # pause | resume
CONNECTOR="${2:-order-outbox-connector}"
echo "$(date '+%H:%M:%S') ${ACTION} $CONNECTOR"
curl -s -X PUT "http://localhost:55083/connectors/${CONNECTOR}/${ACTION}"
echo ""
