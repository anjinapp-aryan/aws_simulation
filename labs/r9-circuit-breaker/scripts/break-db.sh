#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
MODE="${1:-cut}"
if [ "$MODE" = "cut" ]; then
  curl -s -X POST http://localhost:64474/proxies/db -d '{"enabled":false}' -H "Content-Type: application/json"
else
  curl -s -X POST http://localhost:64474/proxies/db -d '{"enabled":true}' -H "Content-Type: application/json"
fi
echo ""
