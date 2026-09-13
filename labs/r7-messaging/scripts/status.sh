#!/usr/bin/env bash
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
echo "--- containers ---"
docker compose ps
echo ""
echo "--- real queue state (RabbitMQ Management API) ---"
curl -s -u guest:guest "http://localhost:62672/api/queues" | python -c "
import sys,json
d=json.load(sys.stdin)
for q in d:
    print(f\"{q['name']:16s} ready={q.get('messages_ready',0):4d} unacked={q.get('messages_unacknowledged',0):4d} consumers={q.get('consumers',0)}\")
"
