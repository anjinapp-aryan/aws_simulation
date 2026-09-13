#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$(cd ../../.tools && pwd):$PATH"
export KUBECONFIG="$HOME/.kube/config"

echo "creating real kind cluster (3 nodes: 1 control-plane + 2 workers)..."
kind create cluster --config kind-config.yaml

echo "building app image and loading into kind..."
docker build -t r10-app:v1 ./app
kind load docker-image r10-app:v1 --name r10

echo "installing metrics-server (official, kind-patched for insecure kubelet TLS)..."
kubectl apply -f monitoring/metrics-server.yaml

echo "installing kube-state-metrics (official standard manifests, applied directly)..."
kubectl apply -k github.com/kubernetes/kube-state-metrics/examples/standard

echo "deploying Prometheus + Grafana..."
kubectl apply -f monitoring/prometheus.yaml
kubectl apply -f monitoring/grafana.yaml

echo "deploying the app..."
kubectl apply -f manifests/deployment.yaml
kubectl apply -f manifests/service.yaml
kubectl apply -f manifests/hpa.yaml

echo "waiting for app pods ready..."
kubectl wait --for=condition=Ready pod -l app=r10-app --timeout=120s

echo ""
echo "R10 cluster up."
echo "App (NodePort)  : http://localhost:65080"
echo "Grafana         : http://localhost:65300"
echo "Prometheus      : http://localhost:65090"
echo "kubectl get pods -w   (real live state)"
