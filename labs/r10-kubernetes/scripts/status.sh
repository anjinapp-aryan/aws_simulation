#!/usr/bin/env bash
cd "$(dirname "$0")/.."
export PATH="$(cd ../../.tools && pwd):$PATH"
echo "--- nodes ---"
kubectl get nodes -o wide
echo "--- pods ---"
kubectl get pods -o wide
echo "--- deployment ---"
kubectl get deployment r10-app
echo "--- hpa ---"
kubectl get hpa r10-app
echo "--- service endpoints ---"
kubectl get endpoints r10-app
