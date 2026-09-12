#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1

echo "--- starting registry, traefik, dozzle ---"
docker compose up -d registry traefik dozzle
sleep 2

echo "--- building + pushing v1 image to the local registry ---"
bash scripts/build-push.sh v1

echo "--- starting desired_count=2 (app-1, app-2) ---"
docker compose up -d app-1 app-2
sleep 3

echo ""
echo "Traefik traffic:   http://localhost:38080/"
echo "Traefik dashboard: http://localhost:38081/dashboard/"
echo "Dozzle logs:       http://localhost:38888/"
echo "Local registry:    http://localhost:5000/v2/_catalog"
echo ""
bash scripts/status.sh
