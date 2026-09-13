#!/usr/bin/env bash
# R12-07: a REAL, common NetworkPolicy mistake - remove the DNS-allow rule
# while default-deny egress is still active, breaking DNS resolution.
set -euo pipefail
cd "$(dirname "$0")/.."
kubectl.exe delete networkpolicy allow-dns-egress
echo "--- attempting DNS-dependent connection (expect failure) ---"
kubectl.exe exec deploy/frontend -- curl -s -o /dev/null -w "HTTP %{http_code}\n" --max-time 4 http://backend/health || echo "FAILED as expected - investigate with scripts/status.sh and hubble"
kubectl.exe exec deploy/frontend -- sh -c "timeout 4 nslookup backend" || echo "DNS resolution FAILED (real root cause)"
