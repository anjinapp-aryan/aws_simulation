#!/usr/bin/env bash
# Real connectivity probes reused by every experiment: frontend->backend,
# backend->database, and the unauthorized frontend->database attempt.
# Uses python3's socket module for the raw TCP probe (real bug found: the
# app image's /bin/sh is dash, which does NOT support bash's /dev/tcp
# pseudo-device - python3 is guaranteed present in this image instead).
set -uo pipefail
cd "$(dirname "$0")/.."
TCP_CHECK='import socket,sys
s=socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(4)
try:
    s.connect((sys.argv[1], int(sys.argv[2])))
    print("TCP connect OK")
except Exception as e:
    print(f"TCP connect FAILED: {type(e).__name__}: {e}")
'
echo "--- frontend -> backend (expected allowed) ---"
kubectl.exe exec deploy/frontend -- curl -s -o /dev/null -w "HTTP %{http_code} (%{time_total}s)\n" --max-time 4 http://backend/health
echo "--- backend -> database (expected allowed, real TCP probe) ---"
kubectl.exe exec deploy/backend -- python3 -c "$TCP_CHECK" database 5432
echo "--- frontend -> database DIRECT (expected DENIED - zero trust) ---"
kubectl.exe exec deploy/frontend -- python3 -c "$TCP_CHECK" database 5432
