# R13-06 — INCIDENT: Intermittent backend-to-database failures after a rollout

**Symptom:** since a new backend replica was rolled out, some fraction of backend requests that need the database fail/time out. Others succeed. Nothing was "changed" in application code.

## Available tools
- `kubectl get pods --show-labels`
- `hubble observe` (real flow data) — run via the same per-node-agent targeting pattern R12 already established
- `kubectl exec` into pods to test connectivity directly

## Task
Follow the 12-step investigation. Which pods are affected? What do their labels look like compared to the ones that work? What does Hubble say about the denied traffic specifically?
