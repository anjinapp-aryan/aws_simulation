# R13-04 — INCIDENT: Pod restarts climbing

**Symptom:** `kubectl get pods` shows a rising `RESTARTS` count for the app deployment. Users occasionally see connection failures during the brief windows the pod is down.

## Available tools
- `kubectl get pods`, `kubectl describe pod <name>`, `kubectl get events --sort-by=.lastTimestamp`
- App: `curl http://localhost:64080/`

## Task
Follow the 12-step investigation. What does `kubectl describe pod` say about the LAST termination? Is this a liveness-probe kill, an OOMKill, or something else? Is it random, or does the same pod keep recurring?
