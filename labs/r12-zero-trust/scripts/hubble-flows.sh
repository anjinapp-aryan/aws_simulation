#!/usr/bin/env bash
# Real Hubble flow evidence - the exact same data Hubble UI renders
# graphically. Real bug found and fixed: `kubectl exec ds/cilium` picks
# whichever agent pod comes first (often the control-plane's), but each
# Cilium agent only observes flows local to ITS OWN node - our app pods
# run on r12-worker, so we must target that node's agent specifically.
set -uo pipefail
cd "$(dirname "$0")/.."
AGENT=$(kubectl.exe -n kube-system get pods -o wide | grep "^cilium-[a-z0-9]*\s" | grep -v envoy | grep -v operator | grep r12-worker | awk '{print $1}')
kubectl.exe -n kube-system exec "$AGENT" -c cilium-agent -- hubble observe --last "${1:-50}" -o compact 2>&1
