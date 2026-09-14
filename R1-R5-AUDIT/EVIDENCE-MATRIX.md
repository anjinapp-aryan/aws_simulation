# R1–R5 Theory vs. Hands-On Matrix

| Phase | Capability | Theory | Code Exists | Runnable | Executed (this session) | Failure Tested | Observed | Independently Verified | Recovery | Root Cause | Final Classification |
|---|---|---|---|---|---|---|---|---|---|---|---|
| R1 | ECS credential vending | ✓ | ✓ | ✓ | ✓ | n/a | ✓ | ✓ | n/a | n/a | REAL |
| R1 | IAM ALLOW/DENY (baseline) | ✓ | ✓ | PARTIAL | ✓ (after manual fix) | n/a | ✓ | ✓ | n/a | ✓ (CRLF root-caused this session) | **MIXED** |
| R1 | IAM break/fix | ✓ | ✓ | PARTIAL | ✗ (not re-run live) | HISTORICAL | HISTORICAL | HISTORICAL | HISTORICAL | n/a | THEORY-CONFIRMED-HISTORICALLY, CURRENT STATUS UNKNOWN |
| R2 | Traffic distribution | ✓ | ✓ | ✓ | ✓ | n/a | ✓ | ✓ | n/a | n/a | **HANDS-ON PROVEN** |
| R2 | Health-check failover | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | n/a | **HANDS-ON PROVEN** |
| R3 | Self-crash/restart | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ (kill-vs-crash distinction) | **HANDS-ON PROVEN** |
| R3 | OOM/mem_limit | ✓ | ✓ | ✓ | ✓ | ✓ | PARTIAL | PARTIAL | ✓ | n/a | HANDS-ON, PARTIALLY VERIFIED (timing) |
| R3 | Scaling | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | n/a | **HANDS-ON PROVEN** |
| R4 | DB connectivity | ✓ | ✓ | ✓ | ✓ | n/a | ✓ | ✓ | n/a | n/a | **HANDS-ON PROVEN** |
| R4 | Latency injection | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | n/a | **HANDS-ON PROVEN** |
| R4 | Pool exhaustion | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | n/a | **HANDS-ON PROVEN** |
| R4 | Network cut / bad creds | ✓ | ✓ | ✓ | ✗ (not re-run) | HISTORICAL | HISTORICAL | HISTORICAL | HISTORICAL | n/a | HISTORICALLY PROVEN, NOT RE-VERIFIED |
| R5 | CPU pressure | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | n/a | **HANDS-ON PROVEN** |
| R5 | cAdvisor per-container metrics | ✓ | ✓ | ✓ | ✓ | n/a | ✓ (broken) | ✓ | n/a | ✓ (already root-caused, re-confirmed) | **IMPLEMENTED BUT CURRENTLY BROKEN (honestly documented)** |
| R5 | Memory pressure | ✓ | ✓ | ✓ | ✗ | HISTORICAL | HISTORICAL | HISTORICAL | HISTORICAL | ✓ (historical, honest) | HISTORICALLY PROVEN, NOT RE-VERIFIED |
| R5 | Cascading failure | ✓ | ✓ | ✓ | ✗ | HISTORICAL | HISTORICAL | HISTORICAL | HISTORICAL | n/a | HISTORICALLY PROVEN, NOT RE-VERIFIED |

No row is marked TRUE based on Markdown claims alone — every ✓ in the "Executed (this session)" column corresponds to a real command run and real output captured during this audit; every "HISTORICAL" label means this audit relied on a pre-existing evidence log, not a fresh Markdown claim, and explicitly did not upgrade it to a current PASS.
