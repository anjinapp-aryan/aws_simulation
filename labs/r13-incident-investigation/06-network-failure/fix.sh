#!/usr/bin/env bash
set -euo pipefail
echo "$(date '+%H:%M:%S') [fix] relabeling backend-v2's pod template: tier backend-v2 -> backend"
kubectl patch deployment backend-v2 --type=json -p '[{"op":"replace","path":"/spec/template/metadata/labels/tier","value":"backend"}]'
kubectl rollout status deployment/backend-v2 --timeout=60s
sleep 3
echo "$(date '+%H:%M:%S') [fix] verifying recovery"
V2POD=$(kubectl get pods -l rollout=v2 -o jsonpath='{.items[0].metadata.name}')
kubectl exec "$V2POD" -- python3 -c "
import socket
s=socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.settimeout(4)
try:
    s.connect(('database', 5432)); print('ALLOWED (fixed)')
except Exception as e:
    print('STILL DENIED', e)
"
