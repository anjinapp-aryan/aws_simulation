#!/usr/bin/env bash
set -euo pipefail
echo "$(date '+%H:%M:%S') [fix] removing DB latency toxic"
curl -s -X DELETE http://localhost:59474/proxies/db/toxics/latency
echo ""
echo "$(date '+%H:%M:%S') [fix] waiting for backlog to drain..."
for i in $(seq 1 24); do
  DEPTH=$(curl -s -u guest:guest http://localhost:59672/api/queues/%2f/orders | python -c "import sys,json;print(json.load(sys.stdin)['messages'])")
  echo "  $(date '+%H:%M:%S') queue depth = $DEPTH"
  [ "$DEPTH" = "0" ] && break
  sleep 3
done
