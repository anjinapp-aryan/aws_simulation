# R3 Runbook

```bash
cd labs/r3-ecs

# Start
bash scripts/run.sh
# -> registry:5000, traefik:38080/38081, dozzle:38888, desired_count=2 (app-1,app-2), image v1 pushed

# Observe
bash scripts/status.sh
bash scripts/test.sh 10
# open http://localhost:38081/dashboard/  and  http://localhost:38888/

# R3-02: manual stop/start
docker compose stop app-1
bash scripts/status.sh
docker compose start app-1

# R3-03: health-only failure
bash scripts/break-health.sh app-1
bash scripts/status.sh
bash scripts/fix-health.sh app-1

# R3-04: real self-crash + auto-restart
bash scripts/crash-task.sh app-2

# R3-05: bad image
bash scripts/bad-image.sh

# R3-06: new version
sed -i 's/VERSION", "1"/VERSION", "2"/' app/server.py
docker build -t localhost:5000/r3-app:v2 ./app && docker push localhost:5000/r3-app:v2

# R3-07: OOM
bash scripts/oom-task.sh

# R3-09: scaling
bash scripts/scale.sh 1
bash scripts/scale.sh 2
bash scripts/scale.sh 3

# R3-10: integrated
docker compose kill app-1 &
bash scripts/test.sh 10
docker compose start app-1

# Stop
bash scripts/cleanup.sh
```
