# R10 — Kubernetes/EKS Fundamentals

Runnable lab: `labs/r10-kubernetes/`. Docs: `GAP-ANALYSIS.md`, `REUSE-AUDIT.md`, `ARCHITECTURE.md`, `R10-REPORT.md` (full results, real bugs found/fixed, PASS status).

Requires `kind` (downloaded to `.tools/kind.exe`, gitignored) and `kubectl` (bundled with Docker Desktop). **Run `kind`/`kubectl` commands via PowerShell, not Git Bash** - a real environment quirk documented in the report (Git Bash's PATH translation breaks `kind.exe`'s own `docker` subprocess lookup).

```powershell
$env:PATH = "D:\WORK_SPACE\aws_simulation\.tools;" + $env:PATH
cd labs\r10-kubernetes
kind.exe create cluster --config kind-config.yaml
docker build -t r10-app:v1 .\app
kind.exe load docker-image r10-app:v1 --name r10
kubectl.exe apply -f monitoring\metrics-server.yaml
kubectl.exe apply -k github.com/kubernetes/kube-state-metrics/examples/standard
kubectl.exe apply -f monitoring\prometheus.yaml
kubectl.exe apply -f monitoring\grafana.yaml
kubectl.exe apply -f manifests\deployment.yaml
kubectl.exe apply -f manifests\service.yaml
kubectl.exe apply -f manifests\hpa.yaml
```

App: `http://localhost:65080`, Grafana: `http://localhost:65300`, Prometheus: `http://localhost:65090`.

Cleanup: `kind.exe delete cluster --name r10` then `docker network rm kind` if it lingers (a real, documented finding - see report).
