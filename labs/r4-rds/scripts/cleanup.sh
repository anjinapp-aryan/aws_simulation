#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose down -v
echo "R4 torn down. AWS spend: \$0."
