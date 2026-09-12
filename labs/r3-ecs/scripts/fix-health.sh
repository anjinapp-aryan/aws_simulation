#!/usr/bin/env bash
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
TASK="${1:-app-1}"
docker compose exec -T "$TASK" rm -f /tmp/unhealthy
echo "$TASK /health restored to 200."
