#!/usr/bin/env bash
# R15 capstone - real end-to-end verification.
#
# A running container is not evidence. Every check below asserts real
# behaviour: Patroni's own cluster view, Envoy's own endpoint health,
# Kafka Connect's own task state, and a real Saga round trip through
# Postgres -> outbox -> Debezium -> Kafka -> payment-service -> back.
#
# Exits non-zero if any check fails. Never reports PASS on absence of proof.
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1

R14="../r14-ha-dr/patroni-src"
PC="docker compose -f $R14/docker-compose.yml"
CONNECT="http://localhost:59083"
APP="http://localhost:59080"
ORDER_ID="verify-$(date +%s)"

PASS=0; FAIL=0
ok()   { echo "  PASS  $*"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }
head_() { echo ""; echo "--- $* ---"; }

cluster_json() {
  for n in patroni1 patroni2 patroni3; do
    $PC exec -T "$n" curl -sf http://localhost:8008/cluster 2>/dev/null && return 0
  done
  return 1
}

# ------------------------------------------------------------ R14 foundation
head_ "R14 foundation (Patroni HA cluster)"
CJ=$(cluster_json || true)
if [ -z "$CJ" ]; then
  bad "Patroni cluster unreachable - R14 prerequisite is not up (run ./scripts/run.sh)"
else
  # Patroni reports a healthy leader as 'running' but a healthy replica as
  # 'streaming' once replication is actually established - both are healthy.
  RUNNING=$(echo "$CJ" | python -c "import json,sys; print(len([m for m in json.load(sys.stdin)['members'] if m.get('state') in ('running','streaming')]))")
  LEADER=$(echo "$CJ" | python -c "import json,sys; print(next((m['name'] for m in json.load(sys.stdin)['members'] if m.get('role')=='leader'), ''))")
  REPLICAS=$(echo "$CJ" | python -c "import json,sys; print(len([m for m in json.load(sys.stdin)['members'] if m.get('role')=='replica' and m.get('state')=='streaming']))")

  [ "$RUNNING" = "3" ] && ok "3 Patroni members healthy" || bad "only $RUNNING/3 Patroni members healthy"
  [ -n "$LEADER" ]     && ok "leader identified: $LEADER" || bad "no leader in the cluster"
  [ "$REPLICAS" = "2" ] && ok "2 replicas streaming" || bad "only $REPLICAS/2 replicas streaming"
  # The order connector is pinned to patroni1 by design (INCIDENT-02's root
  # cause). If patroni1 is not the leader, CDC cannot stream.
  [ "$LEADER" = "patroni1" ] && ok "patroni1 holds the leader role (required by the pinned order connector)" \
                             || bad "leader is '$LEADER', not patroni1 - the pinned order connector cannot create its replication slot"

  WAL=$($PC exec -T "${LEADER:-patroni1}" psql -U postgres -tAc "show wal_level" 2>/dev/null | tr -d '\r\n ')
  [ "$WAL" = "logical" ] && ok "wal_level=logical (logical replication available to Debezium)" \
                         || bad "wal_level='$WAL' - Debezium's pgoutput plugin requires 'logical'"

  PGOK=$($PC exec -T "${LEADER:-patroni1}" psql -U postgres -tAc "select 1" 2>/dev/null | tr -d '\r\n ')
  [ "$PGOK" = "1" ] && ok "PostgreSQL reachable on the leader" || bad "PostgreSQL not reachable on the leader"
fi

# ------------------------------------------------------------- R15 app tier
head_ "R15 application tier"
if curl -sf "$APP/health" >/dev/null 2>&1; then
  ok "order-service healthy through Envoy"
else
  bad "order-service not reachable through Envoy ($APP/health)"
fi

HEALTHY_EP=$(curl -sf http://localhost:59901/clusters 2>/dev/null | grep -c "health_flags::healthy" || true)
if [ "${HEALTHY_EP:-0}" -ge 2 ]; then
  ok "Envoy reports $HEALTHY_EP healthy upstream endpoints (both order-service replicas)"
else
  bad "Envoy reports only ${HEALTHY_EP:-0} healthy endpoints (expected 2)"
fi

# ------------------------------------------------------------- CDC pipeline
head_ "CDC pipeline (Debezium / Kafka Connect)"
check_connector() {
  local name="$1" out
  out=$(curl -sf "$CONNECT/connectors/$name/status" 2>/dev/null) || { bad "$name: not registered"; return; }
  echo "$out" | python -c "
import json,sys
s = json.load(sys.stdin)
cs = s.get('connector', {}).get('state')
ts = [t.get('state') for t in s.get('tasks', [])]
print(cs, ','.join(ts) if ts else 'NO-TASKS')
sys.exit(0 if cs == 'RUNNING' and ts and all(t == 'RUNNING' for t in ts) else 1)" >/tmp/r15_conn_$$ 2>/dev/null \
    && ok "$name RUNNING (connector + task): $(cat /tmp/r15_conn_$$)" \
    || bad "$name not fully RUNNING: $(cat /tmp/r15_conn_$$ 2>/dev/null || echo 'unparseable status')"
  rm -f /tmp/r15_conn_$$
}
check_connector order-outbox-connector
check_connector payment-outbox-connector

# -------------------------------------------------------------- real Saga
# The decisive check: a real order written to the Patroni primary, relayed
# through the real outbox -> Debezium -> Kafka -> payment-service path, and
# confirmed back. Cold consumer groups can take ~27s to rebalance on a first
# run (R11's own documented finding), so this wait is deliberately generous.
head_ "Saga round trip (real CDC relay, order $ORDER_ID)"
CREATE=$(curl -sf "$APP/place-order?id=$ORDER_ID" 2>/dev/null || true)
if echo "$CREATE" | grep -q '"status": "CREATED"'; then
  ok "order placed: CREATED"
else
  bad "place-order did not return CREATED: ${CREATE:-<no response>}"
fi

STATUS=""; waited=0
echo -n "  waiting for CONFIRMED (timeout 120s)"
while [ "$waited" -lt 120 ]; do
  STATUS=$(curl -sf "$APP/order-status?id=$ORDER_ID" 2>/dev/null | python -c "
import json,sys
try: print(json.load(sys.stdin).get('status',''))
except Exception: print('')" 2>/dev/null || echo "")
  [ "$STATUS" = "CONFIRMED" ] && break
  sleep 3; waited=$((waited+3)); echo -n "."
done
echo ""
[ "$STATUS" = "CONFIRMED" ] && ok "Saga completed: CREATED -> CONFIRMED in ~${waited}s (real Kafka/Debezium relay)" \
                            || bad "order stuck at '${STATUS:-unknown}' after ${waited}s - CDC relay is not working end to end"

# ------------------------------------------------------------- cache-aside
# First read must come from the database, the second from the cache. Uses a
# fresh order id so the first read is guaranteed to be a real cache miss.
head_ "Cache-aside behaviour"
CACHE_ID="cache-$(date +%s)"
curl -sf "$APP/place-order?id=$CACHE_ID" >/dev/null 2>&1 || true
S1=$(curl -sf "$APP/order-status?id=$CACHE_ID" 2>/dev/null | python -c "
import json,sys
try: print(json.load(sys.stdin).get('source',''))
except Exception: print('')" 2>/dev/null || echo "")
S2=$(curl -sf "$APP/order-status?id=$CACHE_ID" 2>/dev/null | python -c "
import json,sys
try: print(json.load(sys.stdin).get('source',''))
except Exception: print('')" 2>/dev/null || echo "")
if [ "$S1" = "db" ] && [ "$S2" = "cache" ]; then
  ok "cache-aside verified: first read source=db, second read source=cache"
else
  bad "cache-aside not verified (first='${S1:-none}', second='${S2:-none}'; expected db then cache)"
fi

# ------------------------------------------------------------------ result
echo ""
echo "======================================"
echo "  PASSED: $PASS   FAILED: $FAIL"
echo "======================================"
if [ "$FAIL" -gt 0 ]; then
  echo "R15 VERIFY: FAIL - see the failing checks above. Do not treat this environment as reproduced."
  exit 1
fi
echo "R15 VERIFY: PASS - environment matches R15/BASELINE.md. Ready to run an incident."
