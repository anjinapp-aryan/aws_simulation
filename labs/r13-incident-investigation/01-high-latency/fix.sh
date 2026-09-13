#!/usr/bin/env bash
set -euo pipefail
echo "$(date '+%H:%M:%S') [fix] removing 'latency' toxic from 'db' proxy (immediate mitigation)"
curl -s -X DELETE http://localhost:57474/proxies/db/toxics/latency
echo ""
echo "$(date '+%H:%M:%S') [fix] verifying recovery"
for i in 1 2 3; do
  curl -s -o /dev/null -w "checkout: HTTP %{http_code} time=%{time_total}s\n" "http://localhost:57080/checkout?id=fix$i"
done
