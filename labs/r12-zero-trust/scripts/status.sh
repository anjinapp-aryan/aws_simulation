#!/usr/bin/env bash
cd "$(dirname "$0")/.."
CILIUM="/d/WORK_SPACE/aws_simulation/.tools/cilium.exe"
echo "--- nodes/pods ---"
kubectl.exe get nodes -o wide
kubectl.exe get pods -o wide
echo "--- cilium status ---"
"$CILIUM" status
echo "--- active NetworkPolicies ---"
kubectl.exe get networkpolicy,ciliumnetworkpolicy
