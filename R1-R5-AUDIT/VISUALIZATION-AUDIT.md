# R1–R5 Visualization Audit

| Phase | Visualization claimed | Actually verified this session | Classification |
|---|---|---|---|
| R1 | CLI + a custom ASCII flow diagram (`visualize.sh`) | The ASCII diagram was produced live, but it **mislabeled an `InvalidAccessKeyId` error as a policy DENY** during this session's first (pre-fix) run — a real, current bug in the visualization logic's error-classification, not just a cosmetic issue | **PARTIAL** — the visualization mechanism works, but was demonstrated, live, to currently mis-report the wrong failure class under real conditions |
| R2 | CLI + logs (no dashboard claimed) | Verified via direct `curl` response bodies, which is the correct and sufficient signal for this phase's scope | **PROVEN** (appropriately scoped — not every phase needs a dashboard) |
| R3 | CLI + Traefik dashboard + Dozzle (deliberately no third dashboard, per the lab's own reuse audit) | `docker inspect`/`docker compose ps` used as the actual verification signal this session; Traefik dashboard/Dozzle not independently re-checked this session | **PARTIAL** (CLI path proven; dashboard path not re-verified) |
| R4 | Full Prometheus + Grafana + pgweb stack | `pg_up` metric checked directly via Prometheus's own API and confirmed present with a real value (`1`) — this is the audit's own bar ("verify the relevant metric appears," not "Grafana exists") | **PROVEN** |
| R5 | cAdvisor + Prometheus + Grafana + Dozzle | cAdvisor's dashboard-feeding data source confirmed **empty** (`{}`) despite the container running and being scraped — exactly the "tool exists but is broken" case the audit was designed to catch. Grafana itself was not opened/checked visually this session (Prometheus API was queried directly instead, an equivalent but not identical check) | **PARTIAL — cAdvisor's visualization value is CURRENTLY THEORY ONLY (data literally does not exist to display), correctly and pre-emptively documented as such by the project itself** |

## Standing rule applied throughout
"Grafana exists" was never accepted as proof. Every PROVEN row above corresponds to a specific metric or response body actually queried and read during this session.
