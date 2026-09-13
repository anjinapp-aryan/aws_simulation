# R15 — Evidence Strategy

## Required evidence per incident (following R13's own proven `evidence/` convention)
- Incident start timestamp (when the fault was injected — recorded by `inject.sh`, not shown to the investigator until after).
- Symptom timestamp (when the first observable signal would have crossed an alerting threshold — derived from the actual metric/log data, not assumed).
- Investigation timeline (the investigator's own notes in `investigate.md`, timestamped).
- Relevant metrics (Grafana panel values/screenshots described in evidence text, Prometheus query results saved to `evidence/`).
- Logs (Dozzle output captured to `evidence/`).
- Traces (Jaeger trace IDs and span breakdowns saved to `evidence/`).
- Component health at time of investigation (`patronictl list`, Envoy admin stats, Kafka Connect status, Valkey `INFO stats` — whichever apply).
- Failure injection record (`inject.sh`'s own real command log — the ground truth, revealed only in `reveal.md`).
- Root cause evidence (the specific data point that proves it — e.g., Kafka Connect `PAUSED` status, a specific LSN gap, a specific Envoy ejection stat).
- Mitigation timestamp and recovery timestamp (both real, from `fix.sh`).

## MTTD / MTTR / RTO / RPO — computed only when the scenario actually produces the inputs, never invented
| Metric | Definition used | Applies to |
|---|---|---|
| MTTD (Mean Time To Detect) | symptom-crossing-threshold timestamp − fault-injection timestamp | Every scenario (new metric for this project — R13/R14 measured RTO/RPO but never MTTD) |
| MTTR (Mean Time To Recover) | mitigation-applied timestamp − fault-injection timestamp | Every scenario |
| RTO | service-restored timestamp − fault-injection timestamp | R15-02, R15-04 (Patroni-involving) |
| RPO | measured data-loss window, same methodology as R14 Experiments 4/5 | R15-06 (backup/DR) |

A scenario where a metric doesn't apply (e.g., RPO for a pure cache-latency incident) will say so explicitly rather than reporting a fabricated "0".

## Root cause vs. contributing factor vs. secondary symptom — required separation
Every `reveal.md` must classify each finding into exactly one of these three categories (not just list "the bugs"), matching R15-05's own design (paused connector = root cause; retry-amplified CPU = secondary symptom; the app's unbounded retry policy = contributing factor/architectural weakness, not the trigger).

## Post-incident architectural improvement — required, evidence-grounded
Every scenario's `reveal.md` must end with a proposed architectural change that traces to THAT scenario's own evidence (not a generic "add more monitoring" bullet), and must explicitly name at least one new failure mode or cost the proposed change could introduce (per the capstone's own "what new failure mode could the fix introduce?" requirement).
