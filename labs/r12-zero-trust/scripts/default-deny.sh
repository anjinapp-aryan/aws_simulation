#!/usr/bin/env bash
# R12-02: apply real cluster-wide default-deny NetworkPolicy.
set -euo pipefail
cd "$(dirname "$0")/.."
kubectl.exe apply -f manifests/01-default-deny.yaml
