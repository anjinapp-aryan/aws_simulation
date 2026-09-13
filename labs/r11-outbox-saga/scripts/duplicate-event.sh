#!/usr/bin/env bash
# R11-07: force real Kafka consumer redelivery by resetting a consumer
# group's offset to earliest, using Kafka's own real CLI tools (bundled in
# the apache/kafka image) - no custom duplicate-injection code.
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
GROUP="${1:-order-service}"
TOPIC="${2:-outbox.event.Payment}"
echo "$(date '+%H:%M:%S') resetting consumer group '$GROUP' offsets on '$TOPIC' to earliest (forces real redelivery)"
docker compose exec -T kafka /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 --group "$GROUP" --topic "$TOPIC" \
  --reset-offsets --to-earliest --execute
