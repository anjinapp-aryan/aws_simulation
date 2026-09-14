#!/usr/bin/env bash
# R15 capstone - read-only operational snapshot. Changes nothing.
# Same shape as R11's status.sh, extended with the R14 Patroni foundation.
# The real visualization layer stays the existing mature UIs (Grafana,
# Kafka UI, Jaeger, pgweb, Dozzle, Envoy admin) - this is only the
# terminal-level "what is the system doing right now" view.
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1

R14="../r14-ha-dr/patroni-src"
PC="docker compose -f $R14/docker-compose.yml"

echo "--- R14 Patroni cluster ---"
for n in patroni1 patroni2 patroni3; do
  if $PC exec -T "$n" patronictl list 2>/dev/null; then break; fi
done || echo "Patroni cluster unreachable (R14 prerequisite not running)"

echo ""
echo "--- R15 containers ---"
docker compose ps

echo ""
echo "--- Debezium connectors ---"
for c in order-outbox-connector payment-outbox-connector; do
  echo -n "$c: "
  curl -sf "http://localhost:59083/connectors/$c/status" 2>/dev/null | python -c "
import json,sys
s = json.load(sys.stdin)
print(s['connector']['state'], '| tasks:', ', '.join(t['state'] for t in s.get('tasks', [])) or 'none')" 2>/dev/null \
  || echo "not registered / Connect unreachable"
done

echo ""
echo "--- Envoy upstream endpoints ---"
curl -sf http://localhost:59901/clusters 2>/dev/null | grep "health_flags" || echo "Envoy admin unreachable"

echo ""
echo "--- Toxiproxy proxies and active toxics ---"
curl -sf http://localhost:59474/proxies 2>/dev/null | python -c "
import json,sys
for name, p in json.load(sys.stdin).items():
    tox = ', '.join(f\"{t['type']}({t['name']})\" for t in p.get('toxics', [])) or 'none'
    print(f\"{name}: {p['listen']} -> {p['upstream']} enabled={p['enabled']} toxics={tox}\")" 2>/dev/null \
  || echo "Toxiproxy unreachable"

echo ""
echo "--- Order service (via Envoy) ---"
curl -sf http://localhost:59080/health 2>/dev/null || echo "order-service unreachable"
echo ""
