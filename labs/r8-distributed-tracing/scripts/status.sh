#!/usr/bin/env bash
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
echo "--- containers ---"
docker compose ps
echo ""
echo "--- toxiproxy proxies ---"
curl -s http://localhost:63474/proxies | python -m json.tool
echo ""
echo "--- app /health ---"
curl -s -w " (HTTP %{http_code})\n" http://localhost:63080/health
echo ""
echo "--- jaeger services known ---"
curl -s http://localhost:63686/api/services | python -m json.tool
