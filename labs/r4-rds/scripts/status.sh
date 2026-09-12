#!/usr/bin/env bash
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
echo "--- containers ---"
docker compose ps
echo ""
echo "--- Toxiproxy proxy state ---"
curl -s http://localhost:48474/proxies | python -m json.tool
echo ""
echo "--- real Postgres connection count (via exporter's scraped metric) ---"
curl -s http://localhost:49090/api/v1/query --data-urlencode 'query=pg_stat_activity_count' | python -c "
import sys,json
d=json.load(sys.stdin)
for r in d.get('data',{}).get('result',[]):
    print(r['metric'], '=', r['value'][1])
" 2>&1 || echo "(prometheus not scraped yet)"
