#!/usr/bin/env bash
# The SYMPTOM -> FIRST CHECK -> EVIDENCE diagnostic chain, run for real.
cd "$(dirname "$0")/.."
echo "--- FIRST CHECK: container state ---"
docker compose ps app-1 app-2
echo ""
echo "--- EVIDENCE: direct health probe on each container (bypassing Traefik) ---"
for svc in app-1 app-2; do
  echo -n "$svc /health: "
  docker compose exec -T "$svc" python3 -c "
import urllib.request
try:
    r = urllib.request.urlopen('http://localhost:8000/health', timeout=2)
    print(r.status, r.read().decode().strip())
except Exception as e:
    print('UNREACHABLE -', e)
" 2>&1 || echo "(container not running)"
done
echo ""
echo "--- EVIDENCE: Traefik's own view of the service pool ---"
curl -s http://localhost:18081/api/http/services/backend@file | python -c "
import sys,json
d=json.load(sys.stdin)
print('Configured servers:', d.get('loadBalancer',{}).get('servers'))
print('Health status per server:', d.get('serverStatus'))
"
echo ""
echo "--- EVIDENCE: recent Traefik access log (last 5 lines) ---"
docker compose logs --tail=5 traefik 2>&1 | grep -v "level=warning"
