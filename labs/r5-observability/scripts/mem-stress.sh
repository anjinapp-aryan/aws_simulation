#!/usr/bin/env bash
# R5-03: real memory pressure inside the app container's 128m cgroup limit.
# Polls docker inspect (not a sleep) to actually catch OOMKilled=true live,
# same lesson learned in R3 (fixed sleep missed the transient OOM state).
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
VM_BYTES="${1:-200M}"   # exceeds the 128m cgroup limit on purpose
"$(dirname "$0")/_stage-stress-ng.sh"
APP_CID=$(docker compose ps -q app)
echo "$(date '+%H:%M:%S') starting memory stress: vm-bytes=${VM_BYTES} (container limit=128m)"
docker exec -d "$APP_CID" /tmp/stress-ng --vm 1 --vm-bytes "$VM_BYTES" --vm-keep --timeout 20s

echo "polling docker inspect for OOMKilled..."
for i in $(seq 1 40); do
  OOM=$(docker inspect -f '{{.State.OOMKilled}}' "$APP_CID" 2>/dev/null || echo "?")
  RUNNING=$(docker inspect -f '{{.State.Running}}' "$APP_CID" 2>/dev/null || echo "?")
  echo "$(date '+%H:%M:%S.%3N') OOMKilled=${OOM} Running=${RUNNING}"
  if [ "$OOM" = "true" ]; then
    echo "REAL OOM observed live."
    break
  fi
  APP_CID=$(docker compose ps -q app)  # id changes across restart
  sleep 0.3
done
