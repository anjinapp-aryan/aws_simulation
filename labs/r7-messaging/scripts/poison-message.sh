#!/usr/bin/env bash
# R7-03/R7-04: publish a message that always fails processing, driving
# it through the real orders-retry-1/2/3 TTL-delay queues and into the
# real orders-dlq after 3 attempts.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/produce.sh "poison-$(date +%s)" poison
