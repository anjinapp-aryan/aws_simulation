#!/usr/bin/env bash
# R11-08: stop/start the payment-service consumer container (real, same
# mechanism as R7's consumer stop/start).
set -euo pipefail
cd "$(dirname "$0")/.."
ACTION="${1:-stop}"
docker compose "$ACTION" payment-service
echo "$(date '+%H:%M:%S') payment-service $ACTION"
