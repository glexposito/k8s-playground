#!/usr/bin/env bash
set -euo pipefail

RUNTIME_DIR="/tmp/pulse-port-forward"

info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }

if [[ -d "$RUNTIME_DIR" ]]; then
  for pid_file in "$RUNTIME_DIR"/*.pid; do
    [[ -f "$pid_file" ]] || continue
    PID="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
      kill "$PID" 2>/dev/null || true
    fi
    rm -f "$pid_file"
  done
fi

pkill -f "port-forward svc/pulse-api-dev 8081:8080" 2>/dev/null || true
pkill -f "port-forward svc/pulse-api-stg 8082:8080" 2>/dev/null || true
pkill -f "port-forward svc/pulse-api-prod 8083:8080" 2>/dev/null || true
pkill -f "port-forward -n argocd svc/argocd-server 9000:443" 2>/dev/null || true
success "Port-forwards stopped."

info "Stopping Minikube..."
minikube stop
success "Minikube stopped."
