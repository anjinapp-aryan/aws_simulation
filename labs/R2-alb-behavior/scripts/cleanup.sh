#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose down
echo "R2 torn down. AWS spend: \$0 (nothing was ever created outside Docker)."
