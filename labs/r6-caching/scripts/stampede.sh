#!/usr/bin/env bash
# R6-05: real cache stampede - flush the hot key, then fire concurrent
# real HTTP load (vegeta, reused from R5) at the same instant so many
# requests race to find it missing and all hit Postgres.
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
RATE="${1:-20}"
DURATION="${2:-5s}"

docker compose exec -T valkey-primary valkey-cli del item:1 >/dev/null
echo "$(date '+%H:%M:%S') hot key flushed, firing concurrent load: rate=${RATE}/s duration=${DURATION}"

NET=$(docker compose ps -q traefik | xargs -I{} docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' {})
docker run --rm --network "$NET" peterevans/vegeta:latest \
  sh -c "echo 'GET http://traefik/cached-item?id=1' | vegeta attack -rate=${RATE} -duration=${DURATION} | vegeta report"
