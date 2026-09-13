#!/usr/bin/env bash
# R11-02/R11-03: real Toxiproxy fault injection on Debezium's Kafka publish path.
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
MODE="${1:-cut}"   # cut | latency | restore

case "$MODE" in
  cut)
    echo "$(date '+%H:%M:%S') cutting Debezium's connection to Kafka"
    curl -s -X POST http://localhost:55474/proxies/kafka -d '{"enabled":false}' -H "Content-Type: application/json"
    ;;
  latency)
    echo "$(date '+%H:%M:%S') injecting 3000ms latency on Debezium's Kafka path"
    curl -s -X POST http://localhost:55474/proxies/kafka/toxics \
      -d '{"name":"latency","type":"latency","attributes":{"latency":3000,"jitter":200}}' -H "Content-Type: application/json"
    ;;
  restore)
    echo "$(date '+%H:%M:%S') restoring Debezium's Kafka connection"
    curl -s -X DELETE http://localhost:55474/proxies/kafka/toxics/latency >/dev/null || true
    curl -s -X POST http://localhost:55474/proxies/kafka -d '{"enabled":true}' -H "Content-Type: application/json"
    ;;
  *) echo "usage: break-kafka.sh cut|latency|restore"; exit 1 ;;
esac
echo ""
