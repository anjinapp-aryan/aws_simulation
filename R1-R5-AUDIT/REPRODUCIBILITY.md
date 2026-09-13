# R1–R5 Reproducibility Audit

| Phase | Score | Reason |
|---|---|---|
| R1 | **RED** (core experiment) / YELLOW (with a known, one-line fix) | The 3 container-executed scripts (`provision.sh`, `break-iam.sh`, `fix-iam.sh`) are CRLF-corrupted (Windows line endings) and fail with a real dash syntax error (`set: -: invalid option`) inside the Alpine/`mc` container's real `/bin/sh`. A fresh clone on this exact environment **cannot** reproduce the documented ALLOW/DENY behavior without first manually stripping `\r` from these 3 files — an undocumented, non-obvious prerequisite. Once fixed, reproduction is clean and exact. |
| R2 | **GREEN** | Reproduced end-to-end, zero manual intervention, first attempt. All scripts are host-executed bash and tolerate this checkout's line endings. |
| R3 | **YELLOW** | Core lifecycle experiments (crash, scale) reproduce cleanly. Full reproduction from a from-scratch clone requires running `scripts/build-push.sh` once, which uses `sed -i` to bake a `VERSION` value directly into the committed `app/server.py`, then deletes its own `.bak` — a real, working, but non-idempotent and slightly fragile pattern (repeated runs with different tags progressively rewrite the same file). This session avoided invoking it (pre-built images already existed) specifically to honor the audit's "do not modify R1-R5" constraint, which itself demonstrates the reproducibility risk: an ordinary contributor re-running this script IS expected to mutate a committed file as a side effect of normal use. |
| R4 | **GREEN** | Reproduced end-to-end, zero manual intervention, first attempt. |
| R5 | **GREEN** (for what was tested) / **UNVERIFIED** (for what wasn't) | CPU-pressure and cAdvisor-limitation experiments reproduced cleanly and exactly matched pre-existing documentation. Memory-pressure, cascading-failure, and DB-latency-under-load experiments were not re-run this session (time-boxed audit) — no evidence either way on their current reproducibility; they should not be assumed broken OR working until re-tested. |

## Specific reasons catalogued (per the required Step 12 list)
- **Windows-specific issue (CRLF line endings)**: R1's core scripts — the single most significant reproducibility defect found in this audit. The exact same defect class was already found and fixed in this project's own later R14 work (`patroni/patroni`'s `entrypoint.sh`) but never retroactively applied to R1.
- **Fragile/non-idempotent script (in-place source mutation)**: R3's `build-push.sh`.
- **No missing dependencies, no stale images (beyond the above), no broken host-side scripts, no undocumented commands** were found in R2, R4, or the portions of R3/R5 actually tested.
