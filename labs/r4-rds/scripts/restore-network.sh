#!/usr/bin/env bash
# R4-06: real recovery - re-enable the proxy.
set -euo pipefail
echo "$(date '+%H:%M:%S') re-enabling the postgres proxy"
curl -s -X POST http://localhost:48474/proxies/postgres \
  -H 'Content-Type: application/json' -d '{"enabled":true}'
echo ""
