# R14 — Failures and Fixes (real bugs, investigated per the standing rule)

## Bug 1 — Patroni demo containers crash-looped on startup (blocked all of R14 until fixed)
**SYMPTOM**: `demo-patroni1`/etc. exited immediately after `docker compose up -d`; `docker compose ps` showed no running containers.
**OBSERVE**: `docker logs demo-patroni1` → `/entrypoint.sh: 2: : not found` then `/entrypoint.sh: 18: Syntax error: word unexpected (expecting "in")`.
**HYPOTHESIS 1** (rejected): a real syntax error in the upstream script — rejected because line 18 is a plain `case "$1" in`, valid POSIX sh, and the upstream project is 8700+★ and actively maintained; a broken `case` statement would not have survived.
**HYPOTHESIS 2** (confirmed): line-ending corruption from the Windows checkout.
**EVIDENCE**: `file docker/entrypoint.sh` → "with CRLF line terminators"; `cat -A` showed `^M$` at every line end, including the shebang.
**ROOT CAUSE**: this environment's `git config core.autocrlf=true` (global) rewrote the shallow-cloned repo's LF-only shell/Python scripts to CRLF on checkout. Dash (`/bin/sh` in the container) treats the trailing `\r` as a literal character, not whitespace, so `in\r` never matches the `in` keyword the parser expects.
**FIX**: `sed -i 's/\r$//'` on `docker/entrypoint.sh` and `docker/patroni.env`; rebuild; a second, same-class failure then surfaced (`env: 'python3\r': No such file or directory` from `patronictl.py`'s shebang) — fixed identically on `patroni.py`, `patronictl.py`, `patroni_raft_controller.py`, `postgres0.yml`, `postgres1.yml`, `postgres2.yml`.
**REGRESSION TEST**: rebuild + `docker compose up -d` + `patronictl list` → real healthy 3-node cluster (1 Leader, 2 Replicas streaming, 0 lag). Confirmed stable across a second full down/up cycle.
**LESSON**: on this Windows/Git-Bash environment, any freshly-cloned third-party repo's directly-executed scripts must be checked for CRLF corruption before debugging further — the same underlying class of issue as this project's other standing Windows quirks (MSYS PATH translation, `/dev/tcp`), now generalized to "git checkout can silently corrupt shell/Python shebangs on this machine."

## Bug 2 — `/read-replica` endpoint silently served `/read`'s logic instead
**SYMPTOM**: `curl http://localhost:58500/read-replica` returned the `/read` endpoint's response format (`served_by_replica=False`, full row dump) instead of the intended replica-specific check.
**OBSERVE**: the handler's `if self.path.startswith("/read"): ... return` branch was defined *before* the `/read-replica` branch — Python string prefix-matching means `"/read-replica".startswith("/read")` is `True`, so the general `/read` branch always won first and `return`ed before the more specific branch was ever reached.
**ROOT CAUSE**: route ordering in a linear `if/elif`-by-prefix dispatcher; the more specific route must be checked first.
**FIX**: reordered so `/read-replica` is checked before `/read`.
**REGRESSION TEST**: `curl .../read-replica` → `replica_max_id=1 in_recovery=True` (correct, hits a real replica); `curl .../read` → `served_by_replica=False` (correct, hits the leader) — both endpoints independently verified after the fix.
**LESSON**: the same class of mistake this project has hit before with prefix-based routing (R11/R13's `/order` vs `/order-raw`, `/read` vs `/read-replica`) — always order path-prefix checks most-specific-first.

## Bug 3 — `docker pause` failed to prove data loss in the RPO experiment (Experiment 4, Case B v1)
**SYMPTOM**: paused both replicas, wrote a tagged row that should only exist on the leader, killed the leader, unpaused one replica expecting promotion-without-the-row — but the row was present after all.
**HYPOTHESIS 1** (confirmed): `docker pause` (cgroup freezer) stops a container's process scheduling but does not block the kernel's network stack from accepting bytes into an already-open TCP connection's receive buffer.
**EVIDENCE/TEST**: redesigned the isolation using `docker network disconnect` (a genuine, complete network partition — no TCP path exists at all, not merely a frozen process) instead of `docker pause`, and reran the exact same write/kill/promote sequence.
**RESULT AFTER FIX**: the row was confirmed genuinely absent from the newly-promoted leader (`SELECT` returned 0 rows; `max(id)` was 32 lower than the pre-partition write), proving true, measured, non-zero RPO.
**ROOT CAUSE**: PostgreSQL's async walsender pushes WAL bytes over an already-established TCP connection independent of whether the receiving process is actively scheduled to consume them; a paused (frozen) replica's kernel-level socket buffer can still receive and hold bytes sent in the brief window around the freeze taking effect, so `docker pause` is not equivalent to true network unavailability for this specific purpose.
**REGRESSION TEST**: Case B v2 (network disconnect) reproduced cleanly and gave decisive, correct evidence.
**LESSON**: for genuinely testing "this node received nothing," sever the actual network path (`docker network disconnect`, not `docker pause`) — `pause` is the right tool for "this node's processing is stalled" (Experiment 2's lag test, where that distinction didn't matter) but the wrong tool for "this node never got the data" (this experiment, where it did).
