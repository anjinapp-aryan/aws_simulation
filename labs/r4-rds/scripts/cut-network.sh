#!/usr/bin/env bash
# R4-05: real network cut - disables the Toxiproxy proxy entirely, so the
# underlying TCP connection attempt genuinely fails (real "connection
# refused"/timeout), not a printed message.
set -euo pipefail
echo "$(date '+%H:%M:%S') disabling the postgres proxy (real connection cut)"
curl -s -X POST http://localhost:48474/proxies/postgres \
  -H 'Content-Type: application/json' -d '{"enabled":false}'
echo ""
