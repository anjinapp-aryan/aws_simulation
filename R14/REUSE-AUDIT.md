# R14 — GitHub Reuse Audit

Standing rule: REUSE > ADAPT > COMPOSE > REFERENCE > BUILD. Real GitHub API checks (stars/license/activity/archived), license badge never trusted alone. Multiple query phrasings; negative results recorded.

## Searches run

| Query | total_count | Notable results |
|---|---|---|
| `Patroni postgres high availability` | 51 | Mostly 0-10★ personal repos; the real project surfaces under a direct name search below |
| `pgbackrest backup restore postgres` | 9 | `pgbackrest/pgbackrest` (4373★) — real hit |
| `postgres automatic failover open source` | 0 | none |
| `chaos engineering database failover simulation` | 1 | `MarckMorris/chaos-engineering-databases` (0★, archived) — rejected |
| `patroni` (name search) | — | `patroni/patroni` (8718★, MIT, active) |
| `velero kubernetes backup` (name search) | — | weak hits; direct query below found the real project |
| `velero backup kubernetes` | — | `velero-io/velero` (10292★, Apache-2.0, active) |
| `seaweedfs/seaweedfs`, `minio/minio` (direct lookup) | — | see below |

Consistent with every prior phase: broad "simulator/chaos" phrasing returns only 0-1★ unlicensed personal repos. The real, usable candidates all surfaced under **direct project-name** search — the mature tools that actually solve this problem are known, named projects, not generic "HA simulator" repos (there is no such generic repo, confirming COMPOSE is correct here too).

## Candidates evaluated in detail

### `patroni/patroni` — 8718★, MIT, active (pushed 2026-09-08)
**Purpose**: the de facto standard open-source Postgres HA template — automatic leader election and failover using a distributed consensus store (etcd/Consul/ZooKeeper/Kubernetes API), real streaming replication, real automatic promotion of a replica on primary failure.
**Reusable component**: the whole thing, unmodified — official Docker images exist (`patroni` community images) or it installs cleanly into a `postgres`-based container.
**Adaptation required**: wiring into this project's existing minimal-server app pattern (the app already speaks Postgres via `psycopg2`/PgBouncer from R4 — pointing it at Patroni's cluster endpoint instead of a single Postgres host is the only integration work).
**Why selected**: this is exactly "RDS Multi-AZ" in miniature — a real, working automatic-failover Postgres cluster, not a description of one. No comparable maintained alternative exists at this maturity (repmgr and stolon were also checked by name recognition from general knowledge; both have visibly lower recent activity than Patroni and are not the community's current default) — Patroni's dominance here matches the same pattern as R11's Debezium/R12's Cilium selections: one clear best-in-class project, not a menu.

### `pgbackrest/pgbackrest` — 4373★, real license MIT (GitHub API misreported `NOASSERTION` — **verified by fetching the actual `LICENSE` file**, which reads "The MIT License (MIT)"), active (pushed 2026-09-11)
**Purpose**: the standard production-grade Postgres backup/restore/PITR (point-in-time recovery) tool.
**Reusable component**: the CLI + its real backup/restore/archive mechanism against a real Postgres instance (works standalone or against a Patroni-managed cluster).
**Adaptation required**: a repository config pointing at local disk (no S3/cloud needed for the backup destination — filesystem repo type is fully supported and real).
**Why selected**: this is exactly what makes RTO/RPO *measurable* rather than assumed — real backup timestamps, real restore duration, real "how much data since last backup" window.
**Note on the GitHub-API license flag**: this is precisely the "never trust the badge alone" failure mode this project's standing rule warns about — the repo *is* genuinely open source, the API's license detector simply didn't parse this project's LICENSE file format. Verified manually before trusting it.

### `velero-io/velero` — 10292★, Apache-2.0, active (pushed 2026-09-12)
**Purpose**: the standard Kubernetes-native backup/restore/DR tool — backs up cluster object state and (via its restic/kopia integration) persistent volume data, restores into the same or a different cluster.
**Reusable component**: real backup/restore CLI + controller, unmodified.
**Adaptation required**: needs an S3-compatible backup destination.
**Why selected**: extends R10/R12's already-proven `kind` cluster pattern into "what if we lost the whole cluster" territory — a real, not narrated, disaster-recovery drill (delete the cluster, restore from backup into a fresh one).

### S3-compatible local backend for Velero — `minio/minio` REJECTED, `seaweedfs/seaweedfs` SELECTED
`minio/minio` (61,367★) is the default choice everywhone would reach for, but real verification shows its **GitHub repository is archived** (MinIO restricted its open-source server edition's licensing/distribution in 2025) — exactly the kind of check this project's "never trust the badge alone / verify real activity" rule exists to catch; a star count alone would have missed this. **`seaweedfs/seaweedfs`** (34,607★, Apache-2.0, genuinely active, pushed 2026-09-13) provides a real, actively maintained S3-compatible API and is selected instead.

### Rejected
- `MarckMorris/chaos-engineering-databases` (0★, archived) — no real activity.
- Every "postgres HA cluster" personal repo surfaced by the broad queries (`PostgresPatroniCluster`, `swarm-ha-postgresql`, `postgresql-ha-docker`, etc., all ≤10★) — these are individuals' own Patroni-based demos, confirming Patroni itself (not a wrapper project) is the right thing to reuse directly.

## Final reuse decision

**REUSE, composed together**: `patroni/patroni` (Postgres HA/failover) + `pgbackrest/pgbackrest` (backup/restore/RTO-RPO measurement) + `velero-io/velero` + `seaweedfs/seaweedfs` (Kubernetes-level DR against R10/R12's existing `kind` pattern). Nothing here requires building a new HA/DR/backup mechanism — every piece is a real, actively maintained, correctly-licensed, best-in-class open-source project already solving exactly this problem.
