#!/usr/bin/env bash
# Experiment 5: container keeps running, only /health starts failing.
export MSYS_NO_PATHCONV=1
# Proves "container running" != "backend healthy".
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose exec -T app-1 touch /tmp/unhealthy
echo "app-1's container is still running. Its /health endpoint now returns 500."
