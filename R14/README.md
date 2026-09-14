# R14 — High Availability / Disaster Recovery

Runnable lab: `labs/r14-ha-dr/`. Docs: `ARCHITECTURE.md`, `IMPLEMENTATION.md`, `EXPERIMENT-RESULTS.md` (real failover/backup experiments with measured RTO/RPO), `RTO-RPO.md`, `METRICS-VISUALIZATION.md`, `FINAL-REPORT.md`.

A real 3-node Patroni PostgreSQL cluster (3× Postgres+Patroni, 3× etcd, 1× HAProxy) from the official `patroni/patroni` demo compose, run unmodified, with an app, database UI, logs and metrics layered on top. R14 is also the **prerequisite for R15** — R15 joins this cluster's real Docker network rather than duplicating it.

## START

The lab is three independent compose stacks. The first is required; the other two are additive and can be started or skipped independently.

```bash
cd labs/r14-ha-dr

# 1. REQUIRED - build the Patroni image first.
#    The official patroni/patroni compose references an image named `patroni`
#    that it does not build itself. Skipping this fails with:
#      "pull access denied for patroni, repository does not exist"
cd patroni-src && docker build -t patroni . && cd ..

# 2. REQUIRED - the 3-node HA cluster (also creates the network R15 uses)
docker compose -f patroni-src/docker-compose.yml up -d

# 3. OPTIONAL - app + pgweb + Dozzle
docker compose -f docker-compose.override.yml up -d

# 4. OPTIONAL - Patroni /metrics + postgres_exporter + Prometheus + Grafana
#    (see METRICS-VISUALIZATION.md)
docker compose -f docker-compose.monitoring.yml up -d
```

Verify the cluster is genuinely healthy — one Leader, two Replicas `streaming`, lag 0:

```bash
docker compose -f patroni-src/docker-compose.yml exec -T patroni1 patronictl list
```

## URLs

| Tool | URL |
|---|---|
| App (`/whoami`, `/write`, `/read`, `/read-replica`) | http://localhost:58500 |
| pgweb | http://localhost:58501 |
| Dozzle (logs) | http://localhost:58502 |
| Prometheus | http://localhost:58503 |
| Grafana (dashboard "R14 - Patroni HA/DR") | http://localhost:58504 |
| HAProxy write / read endpoints | `localhost:5000` / `localhost:5001` |

## STOP

```bash
docker compose -f docker-compose.monitoring.yml down -v
docker compose -f docker-compose.override.yml down -v
docker compose -f patroni-src/docker-compose.yml down -v
```

The Patroni stack has no named volumes — tearing it down discards the cluster's data, and the next start elects a fresh leader and resets `wal_level` to its default. That is expected for a lab.

## Notes

- `patroni-src/` is a shallow clone of the official `patroni/patroni` repo (MIT). Its compose file is run **unmodified**; R14's own additions live only in the two `docker-compose.*.yml` files at the lab root.
- Leader election on a fresh cluster is non-deterministic — any of the three nodes can win. Do not assume `patroni1`.
- If you are here to run **R15**, do not follow these steps by hand: `labs/r15-capstone/scripts/run.sh` performs steps 1 and 2 plus the extra configuration R15 needs (`wal_level=logical`, leader placement). See `R15/README.md`.
- Docker credential-helper error (`docker-credential-desktop not found`): remove the `credsStore` key from `~/.docker/config.json`.

Everything runs locally on Docker. AWS spend: **$0**.
