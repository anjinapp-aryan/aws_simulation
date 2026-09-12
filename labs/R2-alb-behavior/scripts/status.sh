#!/usr/bin/env bash
cd "$(dirname "$0")/.."
echo "--- container state ---"
docker compose ps
echo ""
echo "--- Traefik's view of the backend service pool (real-time, from the dashboard API) ---"
curl -s http://localhost:18081/api/http/services/backend@file 2>&1 | python -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print('LoadBalancer servers:', d.get('loadBalancer',{}).get('servers'))
    print('Status per server:', d.get('serverStatus'))
except Exception as e:
    print('(dashboard API not ready yet)', e)
"
