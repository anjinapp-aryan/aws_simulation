# R13-07 — INCIDENT: Database load rising with flat request volume

**Symptom:** Postgres query rate/CPU is climbing even though the number of incoming `/cached-item` requests hasn't changed. No deploy happened.

## Available tools
- Grafana: http://localhost:60300
- Prometheus: http://localhost:60090
- Redis Commander (cache browser/keyspace): http://localhost:60082 (if mapped) or via redis-cli in-container
- Dozzle: http://localhost:60888

## Task
Follow the 12-step investigation. Key question: has the cache hit ratio changed? What does the cache's own memory/eviction stats say?
