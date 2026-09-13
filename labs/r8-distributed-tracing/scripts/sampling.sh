#!/usr/bin/env bash
# R8-09: usage: sampling.sh <ratio e.g. 1.0 or 0.1> <request-count>
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
RATIO="${1:-1.0}"
COUNT="${2:-20}"

echo "restarting app with SAMPLE_RATIO=$RATIO"
docker compose stop app >/dev/null
SAMPLE_RATIO=$RATIO docker compose up -d app >/dev/null
until curl -sf http://localhost:63080/health >/dev/null 2>&1; do sleep 1; done

BEFORE=$(curl -s "http://localhost:63686/api/traces?service=r8-app&limit=2000" | python -c "import sys,json;print(len(json.load(sys.stdin)['data']))")
echo "trace count BEFORE: $BEFORE"

for i in $(seq 1 "$COUNT"); do curl -s "http://localhost:63080/checkout?id=samp-$i" >/dev/null; done

sleep 3
AFTER=$(curl -s "http://localhost:63686/api/traces?service=r8-app&limit=2000" | python -c "import sys,json;print(len(json.load(sys.stdin)['data']))")
echo "trace count AFTER $COUNT requests: $AFTER"
echo "new traces retained: $((AFTER - BEFORE)) out of $COUNT requests sent (ratio=$RATIO)"
