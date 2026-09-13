#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Real, documented finding (same as R10/R12 run.sh): kind.exe must run via
# PowerShell with an explicit native-Windows PATH; nesting the $env:PATH
# assignment through bash's -Command string quoting is unreliable - run
# this step directly via a PowerShell session/tool instead if this fails.
powershell.exe -NoProfile -Command '$env:PATH = "D:\WORK_SPACE\aws_simulation\.tools;" + $env:PATH; kind.exe delete cluster --name r12'
docker network rm kind 2>/dev/null || true
echo "R12 torn down. AWS spend: \$0."
