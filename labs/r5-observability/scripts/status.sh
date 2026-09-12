#!/usr/bin/env bash
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
echo "--- containers ---"
docker compose ps
echo ""
echo "--- Traefik backend health ---"
curl -s http://localhost:58081/api/http/services/backend@file | python -m json.tool
echo ""
echo "--- app /health ---"
curl -s -w " (HTTP %{http_code})\n" http://localhost:58080/health
echo ""
echo "--- cadvisor reachable? ---"
curl -s -o /dev/null -w "cadvisor HTTP %{http_code}\n" http://localhost:58082/healthz
