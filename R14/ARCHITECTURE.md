# R14 — Architecture Proposal: HA / Disaster Recovery / Backup-Restore / RTO-RPO

## 1. Candidate themes compared

| | A: HA/DR/Backup-Restore (RTO/RPO) | B: Capacity Planning / Resource Efficiency | C: Multi-Region / Regional Failure |
|---|---|---|---|
| Senior Architect relevance | Very High — RDS Multi-AZ, DR runbooks are core architect vocabulary | Medium — right-sizing is real but more an SRE/FinOps skill | Very High in theory |
| AWS relevance | Very High (RDS Multi-AZ, AWS Backup, DR strategies) | Medium (EC2/RDS instance sizing) | Very High (Route53 failover, cross-region replication) |
| Production relevance | Very High — every real incident review asks "what was our RTO/RPO here" | Medium | High |
| Interview relevance | Very High — RTO/RPO/active-passive-vs-active-active are FAQ-tier | Medium | High |
| Hands-on feasibility ($0, local) | High — Patroni/pgBackRest/Velero all run fully local | High — load generation + resource metrics all local | **Low** — no honest local primitive for "AWS region"; would require faking network geography |
| Visualization feasibility | High — reuses Grafana/pgweb/Dozzle unmodified | High — reuses Grafana/Prometheus unmodified | Low — nothing meaningful to visualize beyond artificial constructs |
| Ability to inject real failures | High — kill the real leader, corrupt/restore real data, lose the whole cluster | Medium — only synthetic load, not a "failure" per se | N/A locally |
| Ability to observe real recovery | High — real failover time, real restore time, both measurable | Low — "recovery" isn't really the axis here | N/A locally |
| Architectural trade-offs exercised | Active-Passive vs Active-Active, sync vs async replication, backup frequency vs RPO | Over- vs under-provisioning, reactive vs proactive scaling | Would be entirely narrated, not measured — against project discipline |
| Reuse opportunities | Very High — 3 best-in-class, correctly-licensed, actively-maintained projects found | Medium — mostly load-generation tools (k6, vegeta, already used in R9), little new here | Low — nothing to reuse since the underlying primitive doesn't exist locally |

**Recommended theme: A — HA / Disaster Recovery / Backup-Restore / RTO-RPO.**

**Why**: it is the largest genuinely untested capability from the gap analysis, it is unambiguously the highest-value Senior/Architect interview area among the three, it has by far the strongest $0-local feasibility and reuse story (three mature, correctly-license-verified projects doing exactly this), and — critically — every claim it produces (RTO, RPO, replication lag, data-loss window) is a **measured number**, not a narrated concept, which is this project's whole standing discipline. Theme B is a real but secondary gap (folded into one experiment below as a bonus, not the main theme) and Theme C is rejected outright as dishonest to attempt at $0 locally.

## 2. $0 feasibility audit

| Component | Runs as | CPU/RAM (approx) | Local-only? |
|---|---|---|---|
| Patroni + 3x Postgres (1 leader, 2 replicas) + etcd (DCS) | Docker Compose | ~1.5 vCPU, ~1GB RAM total | Yes |
| pgBackRest | Runs inside/alongside the Postgres containers, backs up to a local filesystem repo | Negligible | Yes |
| Grafana + Prometheus + community Patroni dashboard | Docker Compose (already-proven R4/R6/R9 images) | ~0.3 vCPU, ~300MB | Yes |
| pgweb, Dozzle | Docker Compose (already-proven R4/R11 images) | Negligible | Yes |
| Velero + `kind` cluster + SeaweedFS (S3-compatible backend) | `kind` (already-proven R10/R12 pattern) + Docker | ~1 vCPU, ~1GB RAM (on top of the kind cluster's own footprint) | Yes |

No AWS credential, endpoint, or API call anywhere. Total local footprint comparable to R11/R12 (this project's heaviest phases so far).

**REAL**: Patroni's actual leader election and streaming-replication promotion; pgBackRest's actual backup/restore/PITR mechanics; Velero's actual Kubernetes object + volume backup/restore; all replication lag and restore-duration numbers measured, not estimated.
**BEHAVIOR-EQUIVALENT**: this whole stack standing in for RDS Multi-AZ (Patroni + streaming replication is architecturally the same pattern AWS RDS's own Multi-AZ failover uses, just self-managed instead of a managed service) and for AWS Backup/PITR (pgBackRest's mechanics mirror what AWS Backup + RDS automated backups do under the hood).
**NOT POSSIBLE LOCALLY**: real cross-AZ/cross-region network latency and partition characteristics (a local Docker network cannot honestly reproduce AWS's real inter-AZ latency profile or a genuine network partition between physical AZs); AWS's own managed-service SLA guarantees; Route53 DNS failover at the global-DNS layer.

## 3. Proposed architecture

```
Client (curl / load script)
  |
Application (reused R4 minimal server pattern, psycopg2)
  |
Patroni-managed Postgres cluster
  leader <--sync/async streaming replication--> replica-1, replica-2
  |  (leader election + failover via etcd, a real distributed consensus store)
  |
pgBackRest (backup/restore, local filesystem repo)
  |
[separate track] kind cluster running the same app + Postgres
  |
Velero + SeaweedFS (S3-compatible) -- full cluster backup/restore/DR drill
```

| Component | REUSED / ADAPTED / NEW |
|---|---|
| App server (`psycopg2`, minimal HTTP handler) | REUSED — R4's exact `server.py` pattern, pointed at Patroni's leader endpoint instead of a single Postgres host |
| Patroni + etcd + Postgres | REUSED, unmodified (official images) |
| pgBackRest | REUSED, unmodified (official image/package) |
| Grafana + Prometheus + Patroni exporter dashboard | REUSED — same pair as R4/R6/R9; dashboard JSON imported from the community, not written |
| pgweb, Dozzle | REUSED, unmodified (R4/R11 pattern) |
| `kind` cluster | REUSED, unmodified (R10/R12 pattern) |
| Velero + SeaweedFS | REUSED, unmodified (official images/CLI) |
| Fault-injection/investigation harness (`inject.sh`/`evidence/` per experiment) | ADAPTED from R13's proven pattern |
| RTO/RPO measurement scripts (timestamp diffing around a real failover/restore) | NEW — thin, a few dozen lines, justified: no generic library computes "RTO/RPO for my specific lab," this is inherently glue |

No new database, proxy, cache, queue, tracing system, or CNI is built — every heavy-lifting mechanism is one of the three reused projects above.

## 4. Proposed experiments

### R14-01 — Baseline: real 3-node Patroni cluster
**Question**: what does a healthy HA Postgres cluster actually look like end-to-end?
**Observe**: `patronictl list` showing 1 leader + 2 replicas, real streaming replication, app writes/reads succeed through the leader.
**Visualization**: `patronictl list`, Grafana replication-lag panel (near-zero), Dozzle.
**AWS mapping**: RDS Multi-AZ steady state. **Fidelity: REAL.**

### R14-02 — Replication lag under write load
**Question**: how far behind does a replica actually fall under sustained write load, and does it matter?
**Observe**: real replication lag rising under load (Grafana time series), never assumed to be zero.
**AWS mapping**: RDS read-replica lag under load. **Fidelity: REAL.**

### R14-03 — Primary (leader) failure and automatic failover
**Question**: what actually happens, and how long does it actually take, when the primary dies?
**Failure injected**: kill the leader container.
**Observe**: real Patroni leader-election logs (Dozzle), `patronictl list` showing a replica promoted, measured failover duration (leader-death timestamp to new-leader-accepting-writes timestamp).
**Visualization**: Grafana marks the failover event; `patronictl list` before/after.
**AWS mapping**: RDS Multi-AZ automatic failover. **Fidelity: REAL** (this is the actual mechanism, at smaller scale).
**Interview takeaway**: "How does RDS Multi-AZ failover actually work under the hood?" — answered with a real, measured failover, not the AWS docs paraphrased.

### R14-04 — Data-loss window during failover (RPO in practice)
**Question**: is any committed data actually lost during the R14-03 failover, and how much?
**Method**: write a tagged, timestamped row just before killing the leader; check for its presence on the new leader immediately after promotion.
**Observe**: with async replication, a real (small) window where a very recent write can be lost; with synchronous replication enabled, zero loss but higher write latency (measured, not asserted) — a genuine trade-off, not a talking point.
**Visualization**: pgweb showing the exact row set on old leader vs. new leader.
**AWS mapping**: RDS Multi-AZ's synchronous replication guarantee vs. a self-managed async replica — this experiment demonstrates *why* AWS's Multi-AZ specifically uses synchronous replication.
**Fidelity: REAL.**

### R14-05 — Backup and restore (RTO/RPO from a backup, not a live replica)
**Failure injected**: simulate a scenario where replication itself is unavailable (all replicas gone) — the only recovery path is a pgBackRest restore.
**Observe**: real `pgbackrest backup`/`restore` timestamps; measured RTO (time from "restore started" to "cluster accepting writes again"); measured RPO (data written after the last backup but before the simulated loss — genuinely gone, shown via pgweb).
**Visualization**: `pgbackrest info`, pgweb before/after.
**AWS mapping**: RDS automated backups / point-in-time recovery. **Fidelity: REAL.**
**Interview takeaway**: "How do you define and actually measure RTO and RPO?" — answered with two real numbers from two different recovery paths (live failover vs. backup restore), not definitions.

### R14-06 — Active-Passive vs Active-Active trade-off (comparison, not new infra)
**Question**: given R14-01–05's evidence, when would you choose active-passive (what was just built) vs. active-active (multi-leader, conflict-prone)?
**Method**: no new cluster — a structured comparison table populated from R14-01–05's actual measured numbers (failover time, RPO window, write latency under sync replication) plus documented reasoning about what active-active would change (write-conflict resolution complexity, the CAP-theorem trade-off) referencing Patroni's own documented position (it deliberately does NOT support active-active, by design, because of exactly this complexity) as real evidence of why active-passive is the industry-default choice for relational databases.
**Fidelity**: REAL evidence used, comparison reasoning is BEHAVIOR-EQUIVALENT/analytical (no active-active relational cluster is actually stood up — building a second, conflict-prone cluster purely to demonstrate the downside would be new infrastructure for a already-well-evidenced negative result).

### R14-07 — Full cluster loss: Kubernetes-level disaster recovery drill
**Failure injected**: delete the entire `kind` cluster (the ultimate failure domain — not just a pod, not just a node, everything).
**Observe**: `velero restore` into a brand-new `kind` cluster from a SeaweedFS-backed backup; measured RTO for full-cluster recovery; verify application + data state matches pre-loss.
**Visualization**: `velero backup describe` / `velero restore describe`, `kubectl get pods` before/after.
**AWS mapping**: losing an entire EKS cluster / a region-level DR drill using AWS Backup. **Fidelity: REAL** (Velero's actual backup/restore mechanics); **BEHAVIOR-EQUIVALENT** for "this stands in for a regional disaster," since the underlying infrastructure loss is a deleted `kind` cluster on the same machine, not a genuinely separate failure domain.

### R14-08 — Capacity trade-off bonus (folds in Theme B's real gap without a separate phase)
**Question**: does adding replicas for HA cost meaningfully more compute for a workload that doesn't need the read capacity?
**Method**: measure real container resource usage (`docker stats`) for the 1-leader/0-replica vs. 1-leader/2-replica configurations under identical load.
**Observe**: a real, measured resource-cost number attached to the HA decision — "3x the Postgres containers" is a concrete, not hand-waved, cost of the availability gained in R14-01–04.
**Fidelity: REAL** (real measured container resource usage); the AWS-dollar-cost translation is explicitly labeled **INFERRED**, not measured (this project cannot honestly price AWS resources locally).

## 5. Architectural trade-offs taught (with evidence, not assertion)

| Decision | Option A | Option B | Evidence this lab produces |
|---|---|---|---|
| Replication mode | Async (fast writes, real small RPO window) | Sync (zero RPO, measured higher write latency) | R14-04's actual before/after row comparison + measured latency delta |
| Recovery path | Live replica promotion (fast, needs a surviving replica) | Backup restore (slower, works even if all replicas are gone) | R14-03 vs R14-05's two different measured RTOs |
| Topology | Active-Passive (this lab, Patroni's own designed default) | Active-Active (not built — documented why, backed by Patroni's own project stance) | R14-06 |
| HA investment | More replicas (higher availability, higher resource cost) | Fewer replicas (lower cost, slower/no automatic recovery) | R14-08's real `docker stats` numbers |

## 6. Risks / limitations
- Patroni/etcd add real operational complexity (a distributed consensus store to run) — this complexity is itself part of the lesson (HA is not free), not hidden.
- `kind`-based Velero DR drill shares the same machine as the "disaster," so it is explicitly labeled BEHAVIOR-EQUIVALENT for regional DR, not a true independent-failure-domain test — stated honestly, not glossed over.
- Local resource ceiling: running the Patroni cluster and the Velero/`kind` cluster simultaneously may strain a typical dev machine — experiments are sequenced (R14-01–06 torn down before R14-07 starts), matching this project's standing one-lab-at-a-time discipline.

## 7. Stop condition
No code, compose files, or manifests have been written. Awaiting **"[R14] ARCHITECTURE APPROVED"** before Phase B implementation begins.
