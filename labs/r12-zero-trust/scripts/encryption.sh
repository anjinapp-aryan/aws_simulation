#!/usr/bin/env bash
# R12-06: real Cilium transparent encryption (WireGuard).
set -euo pipefail
cd "$(dirname "$0")/.."
CILIUM="/d/WORK_SPACE/aws_simulation/.tools/cilium.exe"
"$CILIUM" config set enable-wireguard true 2>&1 || true
kubectl.exe -n kube-system rollout restart daemonset/cilium
kubectl.exe -n kube-system rollout status daemonset/cilium --timeout=120s
echo "--- real encryption status ---"
"$CILIUM" encrypt status
