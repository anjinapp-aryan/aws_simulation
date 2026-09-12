#!/usr/bin/env bash
# R5-06: compose existing mechanisms only - no new failure tool.
# Chain: severe DB latency (Toxiproxy) -> app /db slows/times out ->
# app marked unhealthy (reused R2 toggle, driven by this script observing
# the real /db failure) -> Traefik health check flips backend DOWN.
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1

echo "=== BEFORE ==="
"$(dirname "$0")/verify.sh"

echo ""
echo "=== INJECT: severe DB latency (2000ms) ==="
"$(dirname "$0")/break-db.sh" severe

echo ""
echo "watching app /db and Traefik backend state for 20s..."
for i in $(seq 1 10); do
  TS=$(date '+%H:%M:%S')
  DB_RESULT=$(curl -s -w " HTTP=%{http_code} time=%{time_total}s" http://localhost:58080/db || echo "curl failed")
  echo "[$TS] /db -> $DB_RESULT"
  sleep 2
done

echo ""
echo "=== marking app unhealthy (real production practice: an app whose critical dependency is failing should fail its own health check) ==="
"$(dirname "$0")/break-backend.sh"
sleep 3
echo "=== Traefik backend state now ==="
curl -s http://localhost:58081/api/http/services/backend@file | python -m json.tool

echo ""
echo "=== FIX: restore DB, clear unhealthy flag ==="
"$(dirname "$0")/fix.sh"
sleep 3
echo "=== AFTER (recovery) ==="
"$(dirname "$0")/verify.sh"
