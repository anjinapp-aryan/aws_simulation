#!/usr/bin/env bash
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
echo "--- containers ---"
docker compose ps
echo ""
echo "--- app breaker status ---"
curl -s http://localhost:64000/breaker-status | python -m json.tool
echo ""
echo "--- envoy cluster health (real admin API) ---"
curl -s http://localhost:64901/clusters | grep -E "app_cluster::.*(health_flags|outlier)"
