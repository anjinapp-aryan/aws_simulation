#!/usr/bin/env bash
# R12-01: baseline, no NetworkPolicies applied yet.
set -uo pipefail
cd "$(dirname "$0")/.."
./scripts/test-flow.sh
