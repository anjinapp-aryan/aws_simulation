#!/usr/bin/env bash
# R6-02: real cache flush against the real Valkey primary.
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
echo "$(date '+%H:%M:%S') flushing valkey-primary"
docker compose exec -T valkey-primary valkey-cli flushall
