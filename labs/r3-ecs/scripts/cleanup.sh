#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
docker rm -f r3-badimage-test 2>&1 | grep -v level=warning || true
docker compose down -v
echo "R3 torn down. AWS spend: \$0."
