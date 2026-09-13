#!/usr/bin/env bash
# R6-06 fix step: this is the one place R6 intentionally does NOT fully
# automate recovery. AWS ElastiCache's endpoint/DNS layer repoints clients
# at the new primary automatically after a Multi-AZ failover - that DNS
# cutover mechanism is NOT reproducible locally (see R6-REPORT.md). Here
# we simulate the effect of that missing piece by asking Sentinel (the
# real source of truth) who the current master is, then repointing
# Toxiproxy's real upstream at it - the manual step a naive, non-Sentinel-
# aware client would otherwise need a human/ops action for.
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1

echo "$(date '+%H:%M:%S') restarting the old primary (Sentinel should reconfigure it as a replica)"
docker compose start valkey-primary || docker compose up -d valkey-primary
sleep 3

MASTER_ADDR=$(docker compose exec -T sentinel valkey-cli -p 26379 sentinel get-master-addr-by-name mymaster | tr -d '\r')
MASTER_HOST=$(echo "$MASTER_ADDR" | head -1)
echo "$(date '+%H:%M:%S') Sentinel reports current master: $MASTER_HOST"

echo "$(date '+%H:%M:%S') repointing Toxiproxy's real upstream at the current master"
curl -s -X DELETE http://localhost:61474/proxies/valkey >/dev/null
curl -s -X POST http://localhost:61474/proxies \
  -d "{\"name\":\"valkey\",\"listen\":\"0.0.0.0:6379\",\"upstream\":\"${MASTER_HOST}:6379\",\"enabled\":true}" \
  -H "Content-Type: application/json"
echo ""
echo "fix applied - app's cache endpoint now points at the real current master"
