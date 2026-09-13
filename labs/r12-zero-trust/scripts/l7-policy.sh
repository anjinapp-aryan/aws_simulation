#!/usr/bin/env bash
# R12-04: real Cilium L7 HTTP-aware policy.
set -euo pipefail
cd "$(dirname "$0")/.."
kubectl.exe apply -f manifests/04-l7-policy.yaml
sleep 3
echo "--- allowed: GET /health ---"
kubectl.exe exec deploy/frontend -- curl -s -o /dev/null -w "HTTP %{http_code}\n" --max-time 4 http://backend/health
echo "--- denied at L7: POST / (TCP allowed, HTTP method not in the L7 policy) ---"
kubectl.exe exec deploy/frontend -- curl -s -o /dev/null -w "HTTP %{http_code}\n" --max-time 4 -X POST http://backend/
