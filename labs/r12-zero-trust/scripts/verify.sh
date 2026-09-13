#!/usr/bin/env bash
cd "$(dirname "$0")/.."
./scripts/status.sh
./scripts/test-flow.sh
