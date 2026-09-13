# R15 — Incident Timeline (real timestamps, consolidated)

| Incident | T0 (fault injected) | Symptom window | T3 (recovered/fixed) | Measured duration |
|---|---|---|---|---|
| 01 | (Toxiproxy toxic added) | avg 3.99s read latency during load | toxic removed, verified 9-17ms | fix immediate once diagnosed |
| 02 | 12:06:13.454 (leader killed) | HTTP 000/500 until 12:07:00 | connector fixed ~min later; 5 orders never recovered | RTO 46.5s (app), permanent partial data gap |
| 03 | 12:09:34.582 (both faults set) | mixed 200/503, elevated cache misses | both faults removed, verified 16/16 non-404 = 200 | fixes applied within same investigation session |
| 04 | 12:12:38.679 (leader killed) | HTTP 000/503 until 12:13:25 | automatic (Patroni + PgBouncer), no manual app fix needed | RTO 46.3s |
| 05 | 12:14:39.607 (connector paused) | orders stuck CREATED, CPU 0.5-0.9%→7-8% during retry storm | 12:16:08.074 (connector resumed), confirmed order recovered ~20s later | root cause fixed in ~1.5 min of investigation |
| 06 | (archive_command typo'd before this session) | `pgbackrest backup` failed after 60s timeout | fixed and re-verified within minutes | discovered pre-emptively, no customer impact |

All timestamps are real, taken from command output and evidence files, never invented.
