#!/usr/bin/env bash
set -euo pipefail
echo "$(date '+%H:%M:%S') [fix] removing timeout toxic from app2's DB path (db2 proxy)"
curl -s -X DELETE http://localhost:58474/proxies/db2/toxics/timeout
echo ""
echo "$(date '+%H:%M:%S') [fix] waiting for Envoy's next health/outlier check cycle..."
sleep 12
echo "$(date '+%H:%M:%S') [fix] verifying recovery (20 requests)"
> evidence/post-fix-results.txt
for i in $(seq 1 20); do
  curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:58080/order-raw?id=postfix$i" >> evidence/post-fix-results.txt
done
sort evidence/post-fix-results.txt | uniq -c
echo "$(date '+%H:%M:%S') [fix] final cluster health:"
curl -s http://localhost:58901/clusters | grep "app_cluster::.*health_flags"
