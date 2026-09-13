#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose stop consumer
echo "$(date '+%H:%M:%S') consumer stopped"
