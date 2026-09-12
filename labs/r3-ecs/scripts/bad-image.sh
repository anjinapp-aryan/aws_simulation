#!/usr/bin/env bash
# R3-05: point app-3 at a tag that was never pushed. Real docker pull failure.
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
docker compose stop app-3 2>&1 | grep -v level=warning || true
docker rm -f r3-ecs-app-3-1 2>&1 | grep -v level=warning || true
echo "$(date '+%H:%M:%S') attempting to start app-3 with a never-pushed tag..."
docker run -d --name r3-badimage-test --network r3-ecs_r3net \
  -e APP_NAME=Task-3 localhost:5000/r3-app:bad 2>&1 || true
echo "(see the error above - this is the real 'image cannot be pulled' failure)"
