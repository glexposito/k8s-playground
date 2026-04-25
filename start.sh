#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_PF_PID_FILE="/tmp/pf-argocd.pid"
ARGOCD_PF_LOG_FILE="/tmp/pf-argocd.log"

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

DEV_URL="$(minikube service pulse-api-dev --url)"
STG_URL="$(minikube service pulse-api-stg --url)"
PROD_URL="$(minikube service pulse-api-prod --url)"

if [[ -f "$ARGOCD_PF_PID_FILE" ]]; then
  OLD_PID="$(cat "$ARGOCD_PF_PID_FILE" 2>/dev/null || true)"
  if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    kill "$OLD_PID" 2>/dev/null || true
  fi
  rm -f "$ARGOCD_PF_PID_FILE"
fi

info "Starting Argo CD port-forward on 9000..."
kubectl port-forward -n argocd svc/argocd-server 9000:443 >"$ARGOCD_PF_LOG_FILE" 2>&1 &
echo "$!" > "$ARGOCD_PF_PID_FILE"

echo ""
success "Ready:"
echo "  Dev:     $DEV_URL"
echo "  Staging: $STG_URL"
echo "  Prod:    $PROD_URL"
echo "  Argo CD: https://localhost:9000"
