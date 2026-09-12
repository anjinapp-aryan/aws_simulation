#!/usr/bin/env bash
# R5-04: reuse the exact R2 unhealthy-toggle mechanism (touch a flag file the
# app's /health handler checks). No new failure mechanism.
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
echo "$(date '+%H:%M:%S') marking app unhealthy"
docker compose exec -T app touch /tmp/unhealthy
