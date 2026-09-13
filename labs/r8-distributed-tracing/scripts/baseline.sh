#!/usr/bin/env bash
# R8-01: fire one real traced request, print the response (includes trace_id).
set -euo pipefail
cd "$(dirname "$0")/.."
ID="${1:-1}"
curl -s -w "\n(HTTP %{http_code}, %{time_total}s)\n" "http://localhost:63080/checkout?id=${ID}"
