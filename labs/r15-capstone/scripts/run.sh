#!/usr/bin/env bash
# R15 capstone - reproducible startup.
#
# Reuses R11's script conventions (scripts/run.sh + status/verify/cleanup,
# Toxiproxy proxy creation via its control API, Debezium registration via
# the real Kafka Connect REST API), extended with the prerequisite handling
# R15 needs and R11 does not: R15's order-side database is R14's official
# 3-node Patroni cluster, joined via the external network patroni-src_demo.
#
# Idempotent: safe to re-run against an already-healthy environment. Never
# destroys data - that is cleanup.sh's job only.
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1

R14="../r14-ha-dr/patroni-src"
PC="docker compose -f $R14/docker-compose.yml"
TOXI="http://localhost:59474"
CONNECT="http://localhost:59083"
APP="http://localhost:59080"

step()  { echo ""; echo "=== $* ==="; }
fail()  { echo "FAILED: $*" >&2; exit 1; }

# wait_for <description> <timeout-seconds> <shell-command> [diagnostic-command]
# Polls a real readiness condition. Never a blind sleep. Always bounded, and
# always prints a useful diagnostic on timeout - a bare test expression
# produces no output of its own, so pass a diagnostic command for those.
wait_for() {
  local desc="$1" timeout="$2" cmd="$3" diag="${4:-}" waited=0
  echo -n "waiting for $desc (timeout ${timeout}s)"
  while ! eval "$cmd" >/dev/null 2>&1; do
    if [ "$waited" -ge "$timeout" ]; then
      echo ""
      echo "--- diagnostic ---" >&2
      eval "${diag:-$cmd}" 2>&1 | tail -20 >&2 || true
      fail "$desc did not become ready within ${timeout}s"
    fi
    sleep 2; waited=$((waited + 2)); echo -n "."
  done
  echo " ok (${waited}s)"
}

patroni_exec() { $PC exec -T "$1" "${@:2}"; }

# Name of the node Patroni itself currently reports as leader ("" if none).
current_leader() {
  for n in patroni1 patroni2 patroni3; do
    local out
    out=$($PC exec -T "$n" curl -sf http://localhost:8008/cluster 2>/dev/null) || continue
    echo "$out" | python -c "
import json,sys
try: members = json.load(sys.stdin)['members']
except Exception: sys.exit(1)
for m in members:
    if m.get('role') == 'leader' and m.get('state') == 'running':
        print(m['name']); break
" 2>/dev/null && return 0
  done
  return 1
}

# Counts members Patroni itself considers healthy. Patroni reports a leader
# as 'running' but a replica as 'streaming' once replication is actually
# established (it is 'running' only briefly, right after start) - so both
# states are healthy and counting only 'running' would never reach 3 on any
# cluster that has finished coming up.
healthy_members() {
  local leader; leader=$(current_leader) || return 1
  $PC exec -T "$leader" curl -sf http://localhost:8008/cluster 2>/dev/null | python -c "
import json,sys
healthy = {'running', 'streaming'}
print(len([m for m in json.load(sys.stdin)['members'] if m.get('state') in healthy]))"
}

# Human-readable cluster dump, used as the diagnostic when a wait times out.
cluster_diag() {
  local leader; leader=$(current_leader 2>/dev/null) || { echo "(no Patroni leader reachable)"; return; }
  $PC exec -T "$leader" patronictl list 2>&1 | grep -v "level=warning" || true
}

# ---------------------------------------------------------------- preflight
step "Preflight"
docker info >/dev/null 2>&1 || fail "Docker is not running. Start Docker Desktop and retry."
echo "Docker ready."

# ------------------------------------------------- R14 prerequisite: image
# The official patroni/patroni compose references an image named `patroni`
# that it does not build itself - it must be built from that repo's own
# Dockerfile first. A plain `docker compose up -d` without this fails with
# "pull access denied for patroni". This is the single step that most often
# blocks a returning learner.
step "R14 prerequisite - Patroni image"
if docker image inspect patroni >/dev/null 2>&1; then
  echo "image 'patroni' already present (skipping build)"
else
  echo "building image 'patroni' from the official patroni/patroni Dockerfile..."
  (cd "$R14" && docker build -t patroni .) || fail "patroni image build failed"
fi

# ------------------------------------------------- R14 prerequisite: cluster
step "R14 prerequisite - 3-node Patroni cluster"
$PC up -d
wait_for "Patroni cluster to elect a leader" 120 "current_leader" cluster_diag
wait_for "all 3 Patroni members healthy" 120 '[ "$(healthy_members)" = "3" ]' cluster_diag
LEADER=$(current_leader)
echo "Patroni leader: $LEADER"

# R15's order-outbox-connector is deliberately pinned to the hostname
# `patroni1` (that pinning is INCIDENT-02's documented root cause and must
# not be "fixed" here). Debezium creates a logical replication slot, which
# only a primary accepts - so patroni1 must hold the leader role before
# connector registration, otherwise registration fails on a read-only node.
if [ "$LEADER" != "patroni1" ]; then
  step "Switching leader to patroni1 (required by the pinned order connector)"
  patroni_exec "$LEADER" patronictl switchover demo --leader "$LEADER" --candidate patroni1 --force
  wait_for "patroni1 to become leader" 90 '[ "$(current_leader)" = "patroni1" ]' cluster_diag
  LEADER=patroni1
fi

# ------------------------------------------- R14 prerequisite: wal_level
# Debezium's pgoutput plugin needs logical replication. Patroni's demo
# cluster defaults to wal_level=replica, so this is set through Patroni's
# own persistent configuration mechanism (the DCS config, via its REST API)
# rather than by editing the vendored official repo, then applied with a
# real rolling restart. Idempotent - skipped entirely if already logical.
step "R14 prerequisite - wal_level=logical"
WAL=$(patroni_exec "$LEADER" psql -U postgres -tAc "show wal_level" | tr -d '\r\n ')
if [ "$WAL" = "logical" ]; then
  echo "wal_level already logical (skipping reconfiguration)"
else
  echo "wal_level is '$WAL' - setting logical via Patroni REST PATCH /config"
  patroni_exec "$LEADER" curl -sf -XPATCH -u admin:admin \
    -d '{"postgresql":{"parameters":{"wal_level":"logical"}}}' \
    http://localhost:8008/config >/dev/null || fail "Patroni PATCH /config failed"
  echo "applying with a real rolling restart (patronictl restart demo --force)"
  patroni_exec "$LEADER" patronictl restart demo --force
  wait_for "cluster healthy after restart" 120 '[ "$(healthy_members)" = "3" ]' cluster_diag
  LEADER=$(current_leader)
  WAL=$(patroni_exec "$LEADER" psql -U postgres -tAc "show wal_level" | tr -d '\r\n ')
  [ "$WAL" = "logical" ] || fail "wal_level is still '$WAL' after restart"
  echo "wal_level now: $WAL"
  # A restart can re-elect; re-assert the patroni1 requirement.
  if [ "$LEADER" != "patroni1" ]; then
    patroni_exec "$LEADER" patronictl switchover demo --leader "$LEADER" --candidate patroni1 --force
    wait_for "patroni1 to become leader again" 90 '[ "$(current_leader)" = "patroni1" ]' cluster_diag
  fi
fi

# ------------------------------------------------------ R15 infrastructure
# Started before the applications so the Toxiproxy proxies the order-service
# connects through already exist when it boots - deterministic ordering
# instead of relying on the app's own connect-retry window.
step "R15 infrastructure"
docker compose up -d toxiproxy valkey kafka payment-db pgbouncer
wait_for "Toxiproxy control API" 60 "curl -sf $TOXI/proxies"

# Real Toxiproxy proxies the standing system runs through (the same proxies
# INCIDENT-01 and INCIDENT-03 attach their toxics to). Created idempotently:
# Toxiproxy returns HTTP 409 if a proxy already exists, which is not an error
# for a re-run.
step "R15 Toxiproxy proxies (orderdb, orderdb2, cache)"
create_proxy() {
  local name="$1" listen="$2" upstream="$3"
  if curl -sf "$TOXI/proxies/$name" >/dev/null 2>&1; then
    echo "proxy '$name' already exists (skipping)"
  else
    curl -sf -X POST "$TOXI/proxies" -H "Content-Type: application/json" \
      -d "{\"name\":\"$name\",\"listen\":\"0.0.0.0:$listen\",\"upstream\":\"$upstream\",\"enabled\":true}" \
      >/dev/null || fail "could not create Toxiproxy proxy '$name'"
    echo "proxy '$name' created ($listen -> $upstream)"
  fi
}
create_proxy orderdb  56000 pgbouncer:6432
create_proxy orderdb2 56010 pgbouncer:6432
create_proxy cache    56001 valkey:6379

# ------------------------------------------------------- R15 applications
step "R15 applications"
docker compose up -d --build
wait_for "order-service via Envoy" 180 "curl -sf $APP/health"

# Both replicas must pass Envoy's own active health check before startup is
# called complete, otherwise a verify run right after startup can legitimately
# see only one healthy endpoint.
#
# Real, observed behaviour worth knowing: order-service takes ~2s to
# initialise its schema, so Envoy's very first health check against a replica
# can land while it is still starting and record a network_failure. Envoy then
# falls back to its default no_traffic_interval (60s) before rechecking an
# idle cluster - so the replica stays flagged /failed_active_hc for up to a
# minute even though it is already serving. Curling /health inside this wait
# is deliberate: it is real cluster traffic, which keeps Envoy on its normal
# 2s interval instead of the idle one.
envoy_endpoints_healthy() {
  curl -sf "$APP/health" >/dev/null 2>&1 || true
  [ "$(curl -sf http://localhost:59901/clusters 2>/dev/null | grep -c 'health_flags::healthy')" = "2" ]
}
wait_for "both order-service replicas healthy in Envoy" 150 "envoy_endpoints_healthy" \
         "curl -sf http://localhost:59901/clusters | grep health_flags"

# ----------------------------------------------------- Debezium connectors
step "Debezium connectors"
wait_for "Kafka Connect REST API" 180 "curl -sf $CONNECT/connectors"

register_connector() {
  local name="$1" file="$2"
  if curl -sf "$CONNECT/connectors/$name" >/dev/null 2>&1; then
    echo "connector '$name' already registered (skipping creation)"
  else
    curl -sf -X POST -H "Content-Type: application/json" \
      "$CONNECT/connectors" -d @"$file" >/dev/null \
      || fail "registering connector '$name' failed"
    echo "connector '$name' registered"
  fi
}
register_connector order-outbox-connector   debezium/order-connector.json
register_connector payment-outbox-connector debezium/payment-connector.json

# HTTP 200 on creation only means Kafka Connect accepted the config. The
# connector's own task can still fail afterwards (a real, easy-to-miss
# distinction this project already hit in R15's build). Wait for the task
# state, not just the connector state.
connector_running() {
  curl -sf "$CONNECT/connectors/$1/status" | python -c "
import json,sys
s = json.load(sys.stdin)
tasks = s.get('tasks', [])
ok = s.get('connector', {}).get('state') == 'RUNNING' and tasks and all(t.get('state') == 'RUNNING' for t in tasks)
sys.exit(0 if ok else 1)"
}
wait_for "order-outbox-connector RUNNING (connector + task)"   120 "connector_running order-outbox-connector"
wait_for "payment-outbox-connector RUNNING (connector + task)" 120 "connector_running payment-outbox-connector"

# ------------------------------------------------------------------- done
step "R15 is up"
cat <<EOF
Order API (via Envoy) : $APP/place-order?id=demo-1
                        $APP/order-status?id=demo-1
Envoy admin           : http://localhost:59901/clusters
Kafka UI              : http://localhost:59180
Jaeger (traces)       : http://localhost:59686
Grafana               : http://localhost:59300
pgweb (order/Patroni) : http://localhost:59081
pgweb (payment-db)    : http://localhost:59082
Dozzle (logs)         : http://localhost:59888
Debezium Connect      : $CONNECT/connectors
Toxiproxy control     : $TOXI/proxies

Next: ./scripts/verify.sh   (proves real end-to-end behaviour, not just "containers are up")
EOF
