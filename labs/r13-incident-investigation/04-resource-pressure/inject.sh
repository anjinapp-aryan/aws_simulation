#!/usr/bin/env bash
# R13-04 hidden fault: real stress-ng memory allocation inside one pod,
# exceeding its real 128Mi limit - same real cgroup OOM mechanism R10-05
# already validated, reused unmodified. Run via bash (kubectl works fine
# from Git Bash, only `kind` itself needs PowerShell).
set -euo pipefail
cd "$(dirname "$0")"
POD=$(kubectl get pods -l app=r10-app -o jsonpath='{.items[0].metadata.name}')
echo "$(date '+%H:%M:%S') [inject] running stress-ng --vm-bytes 300M inside pod $POD (limit is 128Mi)"
kubectl exec "$POD" -- stress-ng --vm 1 --vm-bytes 300M --vm-keep --timeout 30s &
echo "$(date '+%H:%M:%S') [inject] polling pod status every 3s for 45s"
for i in $(seq 1 15); do
  echo "--- $(date '+%H:%M:%S') ---" >> evidence/pod-watch.txt
  kubectl get pods -l app=r10-app -o wide >> evidence/pod-watch.txt
  sleep 3
done
wait || true
echo "$(date '+%H:%M:%S') [inject] done, see evidence/pod-watch.txt"
