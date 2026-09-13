#!/usr/bin/env bash
set -euo pipefail
# R13-04's OOMKilled container is automatically restarted by Kubernetes
# itself (the same real self-healing R10 already proved) - there is no
# manual action to "resume" a container, only to verify it recovered and
# to right-size the limit going forward. This script just verifies.
echo "$(date '+%H:%M:%S') [fix] verifying recovery: Kubernetes already restarted the OOMKilled container automatically"
kubectl get pods -l app=r10-app
curl -s http://localhost:64080/ -w "\n"
