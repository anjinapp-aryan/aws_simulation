#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/network-failure.sh restore
docker compose start consumer 2>&1 | true
echo "$(date '+%H:%M:%S') recovery actions applied"
