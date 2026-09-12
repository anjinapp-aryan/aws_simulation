#!/usr/bin/env bash
set -euo pipefail
echo "$(date '+%H:%M:%S') removing latency toxic"
curl -s -X DELETE http://localhost:48474/proxies/postgres/toxics/latency
echo ""
