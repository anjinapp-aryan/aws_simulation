#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
echo "--- app /health ---"
curl -s -w " (HTTP %{http_code})\n" http://localhost:58080/health
echo "--- app /db ---"
curl -s -w " (HTTP %{http_code})\n" http://localhost:58080/db
echo "--- Traefik backend state ---"
curl -s http://localhost:58081/api/http/services/backend@file | python -m json.tool
