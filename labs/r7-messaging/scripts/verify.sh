#!/usr/bin/env bash
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
./scripts/status.sh
echo ""
echo "--- side effects log (tail) ---"
tail -20 data/side_effects.log 2>/dev/null || echo "(none yet)"
echo "--- idempotency store (tail) ---"
tail -20 data/processed_ids.log 2>/dev/null || echo "(none yet)"
echo "--- order completion log (tail) ---"
tail -20 data/order_completion.log 2>/dev/null || echo "(none yet)"
