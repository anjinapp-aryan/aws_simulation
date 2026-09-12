#!/usr/bin/env bash
# R4-04: real Toxiproxy latency toxic - real added delay on real TCP traffic.
set -euo pipefail
MS="${1:-2000}"
echo "$(date '+%H:%M:%S') adding ${MS}ms latency via Toxiproxy"
curl -s -X POST http://localhost:48474/proxies/postgres/toxics \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"latency\",\"type\":\"latency\",\"attributes\":{\"latency\":${MS},\"jitter\":100}}"
echo ""
