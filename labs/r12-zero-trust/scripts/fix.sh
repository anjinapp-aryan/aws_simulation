#!/usr/bin/env bash
# R12-07 fix: restore the DNS-allow rule.
set -euo pipefail
cd "$(dirname "$0")/.."
kubectl.exe apply -f manifests/02-allow-dns.yaml
sleep 2
echo "--- verifying recovery ---"
kubectl.exe exec deploy/frontend -- sh -c "timeout 4 nslookup backend" && echo "DNS resolution RECOVERED"
kubectl.exe exec deploy/frontend -- curl -s -o /dev/null -w "HTTP %{http_code}\n" --max-time 4 http://backend/health
