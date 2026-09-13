#!/usr/bin/env bash
# NOTE (real, documented Windows/Git-Bash finding, same as R10): kind.exe's
# own docker subprocess lookup breaks under Git Bash's MSYS PATH translation.
# `kind create/delete cluster` MUST run via PowerShell. cilium.exe/kubectl.exe
# talk to the Kubernetes API directly (no docker subprocess) and work fine
# from either shell.
set -euo pipefail
cd "$(dirname "$0")/.."
CILIUM="/d/WORK_SPACE/aws_simulation/.tools/cilium.exe"

echo "creating real kind cluster (CNI disabled, Cilium will provide it) via PowerShell..."
powershell.exe -NoProfile -Command "\$env:PATH='D:\WORK_SPACE\aws_simulation\.tools;'+\$env:PATH; kind.exe create cluster --config kind-config.yaml"

echo "building app image and loading into kind..."
docker build -t r12-app:v1 ./app
"$KIND" load docker-image r12-app:v1 --name r12

echo "installing real Cilium CNI (this replaces kindnet)..."
"$CILIUM" install --wait

echo "enabling real Hubble + Hubble UI..."
"$CILIUM" hubble enable --ui
"$CILIUM" status --wait

echo "deploying 3-tier app (frontend/backend/database)..."
kubectl.exe apply -f manifests/00-app.yaml
kubectl.exe wait --for=condition=Ready pod -l app=frontend --timeout=120s
kubectl.exe wait --for=condition=Ready pod -l app=backend --timeout=120s
kubectl.exe wait --for=condition=Ready pod -l app=database --timeout=120s

echo ""
echo "R12 stack up (no NetworkPolicies applied yet - baseline allow-all)."
echo "Run scripts/status.sh, scripts/baseline.sh, etc."
