#!/usr/bin/env bash
set -euo pipefail

ARGOCD_PF_PID_FILE="/tmp/pf-argocd.pid"

info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }

if [[ -f "$ARGOCD_PF_PID_FILE" ]]; then
  PID="$(cat "$ARGOCD_PF_PID_FILE" 2>/dev/null || true)"
  if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    success "Argo CD port-forward stopped."
  else
    info "Argo CD port-forward not running."
  fi
  rm -f "$ARGOCD_PF_PID_FILE"
else
  info "No Argo CD port-forward PID file."
fi

info "Stopping Minikube..."
minikube stop
success "Minikube stopped."
