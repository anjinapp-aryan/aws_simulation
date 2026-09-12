#!/usr/bin/env bash
# R3-04: the APPLICATION crashes itself (os._exit(1)) - not an external
# docker kill. This distinction is real and matters: investigation during
# this run found `docker kill`/`docker stop` do NOT trigger Docker's
# `restart: on-failure` policy (a manual stop is deliberately not treated
# as a crash). A process exiting on its own IS treated as a crash, and
# Docker's restart policy reacts to it automatically - which is what this
# script demonstrates.
set -uo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
TASK="${1:-app-2}"
echo "$(date '+%H:%M:%S') triggering self-crash on $TASK via /crash"
docker compose exec -T "$TASK" python3 -c "
import urllib.request
print(urllib.request.urlopen('http://localhost:8000/crash', timeout=3).read().decode())
"
sleep 2
echo "$(date '+%H:%M:%S') container state immediately after crash:"
docker compose ps -a "$TASK" 2>&1 | grep -v level=warning
docker inspect "r3-ecs-${TASK}-1" --format 'Status={{.State.Status}} ExitCode={{.State.ExitCode}} RestartCount={{.RestartCount}}' 2>&1
