#!/usr/bin/env bash
# R7-06: reuse the exact Toxiproxy mechanism from R4/R5/R6, retargeted at RabbitMQ's AMQP port.
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
MODE="${1:-cut}"   # cut | latency | restore

case "$MODE" in
  cut)
    echo "$(date '+%H:%M:%S') cutting RabbitMQ connectivity"
    curl -s -X POST http://localhost:62474/proxies/rabbitmq -d '{"enabled":false}' -H "Content-Type: application/json"
    ;;
  latency)
    echo "$(date '+%H:%M:%S') injecting 1000ms RabbitMQ latency"
    curl -s -X POST http://localhost:62474/proxies/rabbitmq/toxics \
      -d '{"name":"latency","type":"latency","attributes":{"latency":1000,"jitter":100}}' \
      -H "Content-Type: application/json"
    ;;
  restore)
    echo "$(date '+%H:%M:%S') restoring RabbitMQ connectivity"
    curl -s -X DELETE http://localhost:62474/proxies/rabbitmq/toxics/latency >/dev/null || true
    curl -s -X POST http://localhost:62474/proxies/rabbitmq -d '{"enabled":true}' -H "Content-Type: application/json"
    ;;
  *)
    echo "usage: network-failure.sh cut|latency|restore"; exit 1 ;;
esac
echo ""
