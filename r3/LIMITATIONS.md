# R3 Limitations (stated plainly, not buried)

1. **Task replacement = same container restarting**, not a new task ID. Real ECS always launches a fresh task. Documented at every occurrence in `R3-REPORT.md` §G/L.
2. **No auto-reconciliation on manual stop.** `docker kill`/`stop` does not trigger Docker's restart policy — confirmed by real investigation, not assumed. Real ECS's desired-count enforcement would replace the task automatically; here it needs an explicit `docker compose start`.
3. **Traefik's backend list is static** (3 entries, always present in `traefik-dynamic.yml`); "scaling" works because Traefik's own health check marks stopped backends DOWN, not because of any auto-discovery. Adding a 4th task would mean editing the file.
4. **No real Fargate isolation** — all containers share the host kernel; Fargate provisions per-task microVM-level isolation.
5. **IAM/task-role not exercised in R3** — deliberately out of scope; already covered in R1, not re-demonstrated here to avoid scope creep.
6. **Health-check cadence timing artifacts**: a freshly-scaled task can show DOWN for a couple of seconds before its first successful probe — real, expected behavior, occasionally caught mid-transition during evidence capture (see R3-09 in `R3-REPORT.md` §H).
7. **Dozzle/Traefik are not CloudWatch/ALB** — full fidelity statement in `AWS-MAPPING.md`.
