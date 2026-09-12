#!/usr/bin/env bash
# Real runtime failure - actually stops the container. Nothing about
# Traefik's config is touched.
set -euo pipefail
cd "$(dirname "$0")/.."
echo "Stopping app-1 (real container stop, not a config edit)..."
docker compose stop app-1
echo "Done. app-1 is now actually not running."
