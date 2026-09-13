# R14 — Visualization Audit

Standing rule: reuse mature open-source UIs before building anything custom. No custom dashboard for R14.

## What will be visualized, and with what

| Signal | Tool | Status | What I will see | Which experiment |
|---|---|---|---|---|
| Postgres cluster topology, leader/replica roles, replication lag | `patronictl list` (Patroni's own real CLI, authoritative cluster state) | REUSE, unmodified | Real-time leader/replica/lag table — the same view a Patroni operator uses in production | All HA/failover experiments |
| Postgres cluster metrics over time (replication lag graph, failover event markers) | Grafana + Prometheus (already proven in R4/R6/R9, community Patroni Prometheus exporter) | REUSE — same Grafana/Prometheus pair used in 5 prior phases, new dashboard JSON only (declarative config, not code) | A real time-series graph of replication lag before/during/after a forced failover | Replication-lag and failover-timing experiments |
| DB row-level state before/after restore | pgweb (already proven in R4/R11 pattern) | REUSE, unmodified | Literal table contents — proves exactly which rows existed at backup time vs. which are missing after a restore (the real RPO evidence) | Backup/restore, RPO measurement |
| Backup/restore operation state and timing | `pgbackrest info` (pgBackRest's own real CLI) | REUSE, unmodified | Real backup set list with real timestamps and sizes — the actual evidence RTO/RPO numbers are computed from | Backup/restore, RTO/RPO measurement |
| Kubernetes-level backup/restore/DR state | `velero backup describe` / `velero restore describe` / `kubectl get pods` (Velero's own real CLI) | REUSE, unmodified | Real backup completion status, real restore progress, real pod re-creation after a full cluster-loss drill | Cluster-loss DR drill |
| Container logs during failover | Dozzle (already proven in every compose-based phase) | REUSE, unmodified | Real-time Patroni/Postgres logs showing the actual leader-election decision as it happens | All failover experiments |

## Considered and rejected as primary evidence
- `otwld/velero-ui` (137★, Apache-2.0, active) — a real, existing web UI for Velero. Genuinely usable, but far less mature/battle-tested than this project's other visualization choices (Grafana, Hubble, Kafka UI all have thousands of stars and years of production use). **Classified as optional/stretch, not primary** — `velero` CLI output remains the authoritative evidence source, consistent with how this project has always treated CLI/API output as ground truth (Envoy admin stats, Hubble flow data) with a UI as a secondary, nice-to-have lens.
- A custom Patroni dashboard: rejected outright — `patronictl list` plus a community-maintained Patroni Grafana dashboard (declarative JSON, imported not written) already covers this; no custom code needed.

## Why this satisfies "visualization is mandatory"
Every experiment's key evidence (who's the leader, how far behind is the replica, how much data would be lost, how long did recovery take) is visible through an existing, mature, real tool's own live output — never asserted from a script's own print statements.
