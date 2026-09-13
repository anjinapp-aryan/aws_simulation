#!/usr/bin/env bash
# usage: produce.sh <id> <type: normal|poison|crash|crash_idempotent|ordered> [seq] [delay_ms]
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
docker compose run --rm producer "$@"
