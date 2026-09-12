#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose down -v
rm -f /tmp/r5-stress-ng-bin
echo "R5 torn down. AWS spend: \$0."
