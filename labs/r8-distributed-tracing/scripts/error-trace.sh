#!/usr/bin/env bash
# R8-07: deliberate application failure (?fail=1), real error span.
set -euo pipefail
cd "$(dirname "$0")/.."
curl -s -w "\n(HTTP %{http_code})\n" "http://localhost:63080/checkout?id=err1&fail=1"
