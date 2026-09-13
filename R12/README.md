# R12 — Kubernetes Network Security / Zero-Trust

Runnable lab: `labs/r12-zero-trust/`. Docs: `GAP-ANALYSIS.md`, `REUSE-AUDIT.md`, `ARCHITECTURE.md`, `R12-REPORT.md` (full results, real bugs found/fixed, PASS status).

Requires `kind` and `cilium-cli` (both in `.tools/`, gitignored) and `kubectl`. **Run `kind`/`cilium` commands via PowerShell, not Git Bash** - the same real environment quirk documented in R10 (Git Bash's PATH translation breaks the native `.exe`'s own `docker` subprocess lookup).

```powershell
$env:PATH = "D:\WORK_SPACE\aws_simulation\.tools;" + $env:PATH
cd labs\r12-zero-trust
kind.exe create cluster --config kind-config.yaml
docker build -t r12-app:v1 .\app
kind.exe load docker-image r12-app:v1 --name r12
cilium.exe install --wait
cilium.exe hubble enable --ui
kubectl.exe apply -f manifests\00-app.yaml
```

Then from Git Bash (kubectl/cilium work fine there, only `kind` needs PowerShell):
```bash
cd labs/r12-zero-trust
./scripts/baseline.sh          # R12-01
./scripts/default-deny.sh      # R12-02
./scripts/allow-policy.sh      # R12-03
./scripts/l7-policy.sh         # R12-04
./scripts/rogue-pod.sh         # R12-05
./scripts/encryption.sh        # R12-06
./scripts/break-dns.sh && ./scripts/fix.sh   # R12-07
./scripts/hubble-flows.sh 50   # real flow evidence, any time
./scripts/cleanup.sh
```
