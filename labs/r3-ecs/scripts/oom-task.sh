#!/usr/bin/env bash
# R3-07: real memory pressure against a real mem_limit (128m in compose).
# Hits /oom, which allocates 10MB chunks until the kernel/cgroup OOM-kills it.
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
TASK_URL="http://localhost:38080/"
echo "$(date '+%H:%M:%S') triggering /oom on app-1 (mem_limit=128m)..."
docker compose exec -T app-1 python3 -c "
import urllib.request
try:
    urllib.request.urlopen('http://localhost:8000/oom', timeout=15)
except Exception as e:
    print('request ended:', e)
" || echo "(exec itself failed - container likely already killed)"
sleep 2
echo "$(date '+%H:%M:%S') container state after OOM attempt:"
docker compose ps app-1
docker inspect r3-ecs-app-1-1 --format '{{.State.OOMKilled}} exitcode={{.State.ExitCode}}' 2>&1 || true
