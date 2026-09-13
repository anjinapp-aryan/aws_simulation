#!/usr/bin/env bash
# R8-05: fire a request and check whether the consumer's Jaeger trace
# shares the same trace_id as the producer's - real proof, not assumed.
set -euo pipefail
cd "$(dirname "$0")/.."
RESP=$(curl -s "http://localhost:63080/checkout?id=async-$(date +%s)")
echo "producer response: $RESP"
TRACE_ID=$(echo "$RESP" | python -c "import sys,json;print(json.load(sys.stdin)['trace_id'])")
echo "trace_id=$TRACE_ID"
sleep 8   # Jaeger's BatchSpanProcessor export delay observed to need ~5-6s
echo "--- jaeger trace detail (should show BOTH r8-app and r8-consumer spans) ---"
curl -s "http://localhost:63686/api/traces/${TRACE_ID}" | python -c "
import sys,json
d=json.load(sys.stdin)
for t in d.get('data',[]):
    services = set()
    for s in t['spans']:
        pid = s['processID']
        services.add(t['processes'][pid]['serviceName'])
    print('services in this trace:', services)
    for s in t['spans']:
        print(' -', s['operationName'], 'service=', t['processes'][s['processID']]['serviceName'])
"
