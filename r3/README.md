# R3 — ECR + ECS/Fargate Simulation

Real local registry + real container lifecycle + real health checks + real crash/OOM/scaling behavior. $0. Full detail: `R3-REPORT.md`. Runnable lab: `labs/r3-ecs/`.

```bash
cd labs/r3-ecs
bash scripts/run.sh          # registry + traefik + dozzle + build/push v1 + desired_count=2
bash scripts/test.sh 6       # send traffic
bash scripts/scale.sh 3      # desired_count -> 3
bash scripts/crash-task.sh app-2     # real self-crash, real auto-restart
bash scripts/break-health.sh app-1   # real health-only failure
bash scripts/bad-image.sh            # real registry 404
bash scripts/oom-task.sh             # real OOM
bash scripts/cleanup.sh
```
