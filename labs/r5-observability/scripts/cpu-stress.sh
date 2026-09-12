#!/usr/bin/env bash
# R5-02: real CPU pressure inside the app container's own cgroup.
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
DURATION="${1:-30}"
WORKERS="${2:-2}"
"$(dirname "$0")/_stage-stress-ng.sh"
APP_CID=$(docker compose ps -q app)
echo "$(date '+%H:%M:%S') starting CPU stress: workers=${WORKERS} duration=${DURATION}s"
docker exec -d "$APP_CID" /tmp/stress-ng --cpu "$WORKERS" --timeout "${DURATION}s"
echo "CPU stress running in background inside app container for ${DURATION}s"
