#!/usr/bin/env bash
# Real HTTP load via tsenart/vegeta (MIT), run as a one-off container on the
# r5net network so it hits Traefik the same way any real client would.
# No official tsenart/vegeta Docker image exists, so this uses the widely
# used community packaging (peterevans/vegeta) of the same real vegeta
# binary - same reasoning already applied to edoburu/pgbouncer in R4.
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
RATE="${1:-10}"
DURATION="${2:-15s}"
TARGET="${3:-/health}"
NET=$(docker compose ps -q traefik | xargs -I{} docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' {})
echo "$(date '+%H:%M:%S') vegeta: rate=${RATE}/s duration=${DURATION} target=${TARGET} network=${NET}"
docker run --rm --network "$NET" peterevans/vegeta:latest \
  sh -c "echo 'GET http://traefik${TARGET}' | vegeta attack -rate=${RATE} -duration=${DURATION} | vegeta report"
