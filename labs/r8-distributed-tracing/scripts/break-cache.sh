#!/usr/bin/env bash
# R8-04: cut/restore real cache connectivity via Toxiproxy.
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
MODE="${1:-cut}"
if [ "$MODE" = "cut" ]; then
  curl -s -X POST http://localhost:63474/proxies/cache -d '{"enabled":false}' -H "Content-Type: application/json"
else
  curl -s -X POST http://localhost:63474/proxies/cache -d '{"enabled":true}' -H "Content-Type: application/json"
fi
echo ""
