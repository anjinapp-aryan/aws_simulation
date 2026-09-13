#!/usr/bin/env bash
# R12-03: real least-privilege allow rules (the core zero-trust proof).
set -euo pipefail
cd "$(dirname "$0")/.."
kubectl.exe apply -f manifests/02-allow-dns.yaml
kubectl.exe apply -f manifests/03-allow-least-privilege.yaml
