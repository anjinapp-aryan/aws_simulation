#!/usr/bin/env bash
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
docker compose exec -T app-1 rm -f /tmp/unhealthy
echo "app-1's /health endpoint restored to 200."
