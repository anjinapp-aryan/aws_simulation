# R15 — Architecture Proposal

## 1. Design principle
Unlike R13 (one throwaway, single-fault stack per scenario), R15 needs **one standing, multi-subsystem system** so an investigator can genuinely lose track of which subsystem is at fault, and so faults can cascade or interact across subsystems. Every component is reused unmodified from R1-R14; the only new work is composing them into one system and writing the multi-fault orchestration/evidence scripts.

## 2. Scope decision: Docker Compose only, no `kind`/Cilium in the standing system
R14's own Experiment 7 discovered real, non-trivial fragility bridging a `kind` cluster's network with external Docker services (the SeaweedFS-outside-the-cluster fix, IP-pinning, etc.). Forcing Cilium/K8s into R15's standing system for one scenario's sake would import that same fragility into every scenario. **Decision: keep R15's standing system 100% Docker Compose** (matching R4/R6/R7/R8/R9/R11/R13's own precedent) — every selected incident scenario is achievable with compose-level fault primitives alone (Toxiproxy, `docker kill`/`pause`/`network disconnect`, Valkey `CONFIG SET`, Kafka Connect REST, Envoy config). K8s/Cilium-specific scenarios (R13's 04/06 pattern) are explicitly out of scope for this capstone's standing system — noted as a real, deliberate scope boundary, not an oversight.

## 3. Architecture

```
Client (curl / load scripts)
   |
   v
Traefik (entry, file-provider)                         [REUSED - R2/R5-R8 pattern]
   |
   v
Application tier (order-service / payment-service,     [REUSED - R11/R13 pattern]
  R4/R13's minimal-server style, extended to touch      [ADAPTED - one app now
  cache + DB + queue/CDC in one composed system)          touches all 3 dependencies]
   |         |                  |
   v         v                  v
 Valkey    Patroni HA Postgres   Kafka + Debezium        [REUSED - R6/R14/R11]
 (cache)   (leader+2 replicas,   (CDC outbox -> Saga)
           etcd DCS, HAProxy)
   |
   v
Envoy (circuit breaking in front of one app replica)     [REUSED - R9/R13]
   |
   v
pgBackRest (backup/restore, local filesystem repo)       [REUSED - R14]

Observability (all REUSED, unmodified):
  Prometheus + Grafana   [R4-R9/R13]
  Jaeger (OTel)          [R8/R13]
  Dozzle                 [most phases]
  Kafka UI               [R11/R13]
  pgweb                  [R4/R11/R13/R14]
  patronictl / pgbackrest info / Envoy admin  [R14/R9]
```

| Component | REUSED / ADAPTED / NEW |
|---|---|
| Traefik | REUSED, unmodified |
| App (order-service/payment-service) | ADAPTED — R11/R13's Saga app pattern extended with a real cache-aside read path (R6/R13 style) and a pool-sized DB connection (R4/R13 style), so all three dependency types are exercised by one app family |
| Valkey | REUSED, unmodified |
| Patroni + etcd + HAProxy | REUSED, unmodified (R14's exact stack) |
| Kafka + Debezium | REUSED, unmodified (R11/R13's exact stack) |
| Envoy | REUSED, unmodified (R9/R13's exact config pattern) |
| pgBackRest | REUSED, unmodified (R14's exact setup) |
| Prometheus/Grafana/Jaeger/Dozzle/Kafka UI/pgweb | REUSED, unmodified |
| Multi-fault orchestration scripts (`inject.sh` sequencing 2+ real faults, `evidence/` capture across subsystems) | NEW — thin, following R13's own proven pattern, the only genuinely new code |

## 4. Failure domains modeled
- **App tier**: single point if not scaled; Envoy fronts 2 replicas (R9/R13 pattern) for the circuit-breaker-relevant scenario.
- **Cache tier**: single Valkey node (deliberately no Sentinel here — keeps the cache-fault scenario's blast radius simple and attributable).
- **DB tier**: full Patroni HA (leader + 2 replicas) — the standing system's most complex failure domain, exercised differently across scenarios (sometimes as background "it's supposed to be resilient" infrastructure, sometimes as the direct fault).
- **Messaging/CDC tier**: Kafka + Debezium connectors — can fail silently (connector pause) independent of the DB or app being healthy.

## 5. Chaos injection points (all reused primitives, see `CHAOS-TOOL-AUDIT.md`)
Toxiproxy in front of Valkey and in front of the DB path; `docker kill`/`pause`/`network disconnect` on Patroni members; Valkey `CONFIG SET maxmemory`; Kafka Connect REST pause/resume; Envoy config edits; `stress-ng` inside the app container for the misleading-CPU-signal scenario.

## 6. Recovery paths available to the investigator (all real, all from R14/R9/R6)
Patroni automatic failover; pgBackRest restore; Envoy outlier ejection/manual replica fix; Valkey `maxmemory` correction; Kafka Connect resume; app restart (for stale-connection-pool recovery complications).
