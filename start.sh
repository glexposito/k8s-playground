#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

step() { echo "==> $*"; }

step "Starting k3s..."
if ! systemctl is-active --quiet k3s; then
  sudo systemctl start k3s
fi
if [ ! -f ~/.kube/config ]; then
  mkdir -p ~/.kube
  sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
  sudo chown "$USER" ~/.kube/config
fi
kubectl wait --for=condition=ready node --all --timeout=60s

step "Installing Argo CD..."
kubectl create namespace argocd 2>/dev/null || true
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s

step "Registering apps with Argo CD..."
kubectl apply -f "$REPO_ROOT/argocd/"

step "Exposing Argo CD..."
kubectl port-forward -n argocd svc/argocd-server 9000:443 &>/dev/null &

ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "Dev:     http://localhost:8081"
echo "Staging: http://localhost:8082"
echo "Prod:    http://localhost:8083"
echo "Argo CD: https://localhost:9000  (admin / $ARGOCD_PASS)"
