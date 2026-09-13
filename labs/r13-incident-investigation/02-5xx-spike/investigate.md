# R13-02 — INCIDENT: Checkout error rate spike

**Business impact:** some fraction of `/checkout` requests through the load balancer (Envoy) are returning HTTP 500. Not all — intermittent.
**Scope:** traffic through Envoy (`:58080`). Direct app access bypasses the LB.

## Available tools
- Envoy admin (real cluster/outlier state): http://localhost:58901/clusters , http://localhost:58901/stats
- Grafana: http://localhost:58300
- Prometheus: http://localhost:58090
- Dozzle: http://localhost:58888

## Task
Investigate via the 12-step structure (symptom → scope → metrics → logs → traces → dependency → hypotheses → elimination → root cause → confirmation → remediation → verification). Do not read `inject.sh`/`reveal.md` first.

Key question to answer with evidence: is the error rate uniform across the backend fleet, or concentrated on one replica? What does Envoy's own outlier-detection state say?
