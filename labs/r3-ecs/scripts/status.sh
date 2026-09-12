#!/usr/bin/env bash
cd "$(dirname "$0")/.."
echo "--- container state ---"
docker compose ps
echo ""
echo "--- Traefik's live view of the backend pool ---"
curl -s http://localhost:38081/api/http/services/backend@file | python -c "
import sys,json
d=json.load(sys.stdin)
print('serverStatus:', d.get('serverStatus'))
"
