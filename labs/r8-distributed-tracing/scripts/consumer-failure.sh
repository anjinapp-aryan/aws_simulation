#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-stop}"
if [ "$MODE" = "stop" ]; then
  docker compose stop consumer
else
  docker compose start consumer
fi
