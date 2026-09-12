#!/usr/bin/env bash
# Sends N requests through Traefik and tallies which backend answered each one.
set -uo pipefail
N="${1:-10}"
declare -A COUNTS
for i in $(seq 1 "$N"); do
  BODY=$(curl -s http://localhost:18080/ 2>&1)
  echo "  [$i] $BODY"
  if echo "$BODY" | grep -q "App-1"; then COUNTS[App-1]=$((${COUNTS[App-1]:-0}+1)); fi
  if echo "$BODY" | grep -q "App-2"; then COUNTS[App-2]=$((${COUNTS[App-2]:-0}+1)); fi
done
echo ""
echo "Tally: App-1=${COUNTS[App-1]:-0}  App-2=${COUNTS[App-2]:-0}  (of $N requests)"
