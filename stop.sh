#!/usr/bin/env bash
set -euo pipefail

info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }

pkill -f "minikube tunnel" 2>/dev/null || true
pkill -f "port-forward -n argocd svc/argocd-server 9000:443" 2>/dev/null || true
success "Tunnel and Argo CD port-forward stopped."

info "Stopping Minikube..."
minikube stop
success "Minikube stopped."
