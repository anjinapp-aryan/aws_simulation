#!/usr/bin/env bash
# R3-09: "desired_count" = which named app-N services are up. Traefik already
# lists all 3 in traefik-dynamic.yml (see run.sh comment) and marks stopped
# ones DOWN via its real health check - proven mechanism from R2/R3-03/04.
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
N="${1:?usage: scale.sh <1|2|3>}"
case "$N" in
  1) docker compose stop app-2 app-3 2>&1 | grep -v level=warning; docker compose up -d app-1 2>&1 | grep -v level=warning ;;
  2) docker compose up -d app-1 app-2 2>&1 | grep -v level=warning; docker compose stop app-3 2>&1 | grep -v level=warning ;;
  3) docker compose up -d app-1 app-2 app-3 2>&1 | grep -v level=warning ;;
  *) echo "N must be 1, 2, or 3"; exit 1 ;;
esac
echo "$(date '+%H:%M:%S') scaled to desired_count=$N"
