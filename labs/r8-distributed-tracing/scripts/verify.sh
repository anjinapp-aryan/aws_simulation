#!/usr/bin/env bash
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
./scripts/status.sh
echo ""
echo "--- baseline checkout ---"
./scripts/baseline.sh 1
