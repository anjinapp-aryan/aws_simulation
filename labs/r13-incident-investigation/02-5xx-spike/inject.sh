#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "$(date '+%H:%M:%S') [inject] setting a timeout toxic on app2's DB path only (db2 proxy)"
curl -s -X POST http://localhost:58474/proxies/db2/toxics \
  -H 'Content-Type: application/json' \
  -d '{"name":"timeout","type":"timeout","attributes":{"timeout":2000}}'
echo ""
echo "$(date '+%H:%M:%S') [inject] generating traffic through Envoy (100 sequential requests)"
> evidence/lb-results.txt
for i in $(seq 1 100); do
  curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:58080/order-raw?id=$i" >> evidence/lb-results.txt
  sleep 0.05
done
echo "$(date '+%H:%M:%S') [inject] done."
