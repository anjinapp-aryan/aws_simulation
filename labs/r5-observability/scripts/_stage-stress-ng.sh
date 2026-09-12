#!/usr/bin/env bash
# Shared helper: copies the real stress-ng static binary (from the official
# ColinIanKing/stress-ng Docker image) into the ALREADY RUNNING app container
# via `docker cp`, so CPU/memory pressure is applied inside the app
# container's own cgroup (real, cAdvisor-visible pressure on that specific
# container) WITHOUT installing stress-ng into the app image or Dockerfile -
# per the explicit rule to keep the application container clean. Idempotent:
# skips the copy if the binary is already staged.
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
APP_CID=$(docker compose ps -q app)

if docker exec "$APP_CID" test -x /tmp/stress-ng 2>/dev/null; then
  echo "stress-ng already staged in app container"
  exit 0
fi

echo "staging real stress-ng binary into app container (one-time)"
docker create --name r5-stress-src colinianking/stress-ng:latest >/dev/null
docker cp r5-stress-src:/usr/bin/stress-ng /tmp/r5-stress-ng-bin
docker rm -f r5-stress-src >/dev/null
docker cp /tmp/r5-stress-ng-bin "$APP_CID":/tmp/stress-ng
docker exec "$APP_CID" chmod +x /tmp/stress-ng
docker exec "$APP_CID" /tmp/stress-ng --version
