#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose up -d --build
echo ""
echo "Waiting for Traefik + backends to register..."
for i in $(seq 1 20); do
  curl -sf http://localhost:18080/ >/dev/null 2>&1 && break
  sleep 1
done
echo ""
echo "Dashboard:  http://localhost:18081/dashboard/"
echo "Traffic:    http://localhost:18080/"
echo ""
bash "$(dirname "$0")/status.sh"
