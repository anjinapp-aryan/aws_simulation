#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose down -v
rm -rf data
echo "R7 torn down. AWS spend: \$0."
