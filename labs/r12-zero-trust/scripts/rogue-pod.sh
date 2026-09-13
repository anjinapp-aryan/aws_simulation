#!/usr/bin/env bash
# R12-05: deploy a real unlabeled "rogue" pod attempting unauthorized access.
set -euo pipefail
cd "$(dirname "$0")/.."
kubectl.exe apply -f manifests/05-rogue-pod.yaml
kubectl.exe wait --for=condition=Ready pod/rogue --timeout=60s
echo "--- rogue -> database (expected DENIED, real python socket probe - same fix as test-flow.sh) ---"
kubectl.exe exec pod/rogue -- python3 -c "
import socket
s=socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(4)
try:
    s.connect(('database', 5432))
    print('TCP connect OK (SHOULD NOT HAPPEN)')
except Exception as e:
    print(f'TCP connect FAILED: {type(e).__name__}: {e} (correct - rogue pod blocked)')
"
echo "--- rogue -> backend (expected DENIED) ---"
kubectl.exe exec pod/rogue -- curl -s -o /dev/null -w "HTTP %{http_code}\n" --max-time 4 http://backend/health || echo "curl failed/timed out (expected)"
