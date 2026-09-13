#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "$(date '+%H:%M:%S') [fix] restoring sane maxmemory (256mb)"
docker compose exec -T valkey-primary valkey-cli CONFIG SET maxmemory 256mb
echo "$(date '+%H:%M:%S') [fix] verifying recovery: same item requested twice should now HIT"
curl -s "http://localhost:60080/cached-item?id=fix1" -w "\n"
curl -s "http://localhost:60080/cached-item?id=fix1" -w "\n"
docker compose exec -T valkey-primary valkey-cli DBSIZE
