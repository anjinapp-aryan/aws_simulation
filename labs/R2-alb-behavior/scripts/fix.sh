#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "Restarting app-1..."
docker compose start app-1
echo "Done. Traefik's health check will mark it healthy again after its next probe interval (2s)."
