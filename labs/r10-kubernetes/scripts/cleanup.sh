#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$(cd ../../.tools && pwd):$PATH"
kind delete cluster --name r10
echo "R10 kind cluster deleted. AWS spend: \$0."
