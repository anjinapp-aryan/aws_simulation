#!/usr/bin/env bash
# R3-03: container stays alive, only /health fails. Same mechanism proven in R2.
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
TASK="${1:-app-1}"
docker compose exec -T "$TASK" touch /tmp/unhealthy
echo "$TASK container still running. /health now returns 500."
