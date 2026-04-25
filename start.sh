#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }
die()     { echo "[ERROR] $*" >&2; exit 1; }

info "Checking required tools..."
for cmd in minikube kubectl helm podman; do
  command -v "$cmd" &>/dev/null || die "$cmd not found. Install it first."
done
success "All required tools found."

info "Starting Minikube..."
minikube start --driver=podman --container-runtime=containerd
success "Minikube started."

info "Installing/ensuring Argo CD..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace

info "Waiting for Argo CD..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s
success "Argo CD server ready."

info "Registering applications..."
kubectl apply -f "$REPO_ROOT/argocd/"
kubectl get applications -n argocd

echo ""
success "Ready:"
echo "Run these in separate terminals and keep them open:"
echo "  minikube tunnel"
echo "  kubectl port-forward -n argocd svc/argocd-server 9000:443"
echo ""
echo "Then get app URLs from services:"
echo "  kubectl get svc pulse-api-dev pulse-api-stg pulse-api-prod"
echo ""
echo "Argo CD: https://localhost:9000"
