#!/usr/bin/env bash
# R13-01 hidden fault injection. Do not read this before investigating.
set -euo pipefail
cd "$(dirname "$0")"
MS="${1:-400}"
echo "$(date '+%H:%M:%S') [inject] adding ${MS}ms latency toxic to the 'db' Toxiproxy proxy"
curl -s -X POST http://localhost:57474/proxies/db/toxics \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"latency\",\"type\":\"latency\",\"attributes\":{\"latency\":${MS},\"jitter\":50}}"
echo ""
echo "$(date '+%H:%M:%S') [inject] generating concurrent checkout load (20 concurrent, 60 total requests) to saturate the 5-connection pgbouncer pool"
for i in $(seq 1 60); do
  ( curl -s -o /dev/null -w "%{http_code} %{time_total}\n" "http://localhost:57080/checkout?id=$i" >> evidence/load-results.txt ) &
  if (( i % 20 == 0 )); then wait; fi
done
wait
echo "$(date '+%H:%M:%S') [inject] done. See evidence/load-results.txt"
