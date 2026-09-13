#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "$(date '+%H:%M:%S') [inject] rolling out backend-v2 (real label typo: tier=backend-v2 instead of tier=backend)"
kubectl apply -f manifests/05-backend-v2.yaml
kubectl wait --for=condition=Ready pod -l rollout=v2 --timeout=60s
echo "$(date '+%H:%M:%S') [inject] testing database connectivity from BOTH backend replicas"
echo "--- original backend pod (tier=backend) ---" | tee evidence/connectivity.txt
kubectl exec deploy/backend -- python3 -c "
import socket
s=socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.settimeout(4)
try:
    s.connect(('database', 5432)); print('ALLOWED')
except Exception as e:
    print('DENIED', e)
" | tee -a evidence/connectivity.txt
echo "--- backend-v2 pod (tier=backend-v2, the new rollout) ---" | tee -a evidence/connectivity.txt
V2POD=$(kubectl get pods -l rollout=v2 -o jsonpath='{.items[0].metadata.name}')
kubectl exec "$V2POD" -- python3 -c "
import socket
s=socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.settimeout(4)
try:
    s.connect(('database', 5432)); print('ALLOWED')
except Exception as e:
    print('DENIED', e)
" | tee -a evidence/connectivity.txt
echo "$(date '+%H:%M:%S') [inject] done, see evidence/connectivity.txt"
