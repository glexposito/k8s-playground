#!/usr/bin/env bash
set -euo pipefail

info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }

pkill -f "port-forward svc/pulse-api-dev 8081:8080" 2>/dev/null || true
pkill -f "port-forward svc/pulse-api-stg 8082:8080" 2>/dev/null || true
pkill -f "port-forward svc/pulse-api-prod 8083:8080" 2>/dev/null || true
pkill -f "port-forward -n argocd svc/argocd-server 9000:443" 2>/dev/null || true
success "Port-forwards stopped."

info "Stopping Minikube..."
minikube stop
success "Minikube stopped."
