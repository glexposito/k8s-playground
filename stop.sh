#!/usr/bin/env bash
set -euo pipefail

HOSTS=(pulse.local dev.pulse.local stg.pulse.local)
RUNTIME_DIR="/tmp/pulse-api-runtime"
TUNNEL_PID_FILE="$RUNTIME_DIR/minikube-tunnel.pid"

info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }
warn()    { echo "[WARN]  $*"; }

stop_tunnel_if_running() {
  local pid_file="$1"
  local pid

  if [[ ! -f "$pid_file" ]]; then
    info "No Minikube tunnel PID file found."
    return 0
  fi

  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    sudo kill "$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    success "Minikube tunnel stopped."
  else
    info "Minikube tunnel process not running."
  fi
  rm -f "$pid_file"
}

# ── 1. Kill tunnel process ───────────────────────────────────────────────────
stop_tunnel_if_running "$TUNNEL_PID_FILE"
pkill -f "port-forward.*ingress-nginx-controller" 2>/dev/null || true
pkill -f "port-forward.*argocd-server" 2>/dev/null || true

# ── 2. Stop Minikube ─────────────────────────────────────────────────────────
info "Stopping Minikube..."
minikube stop
success "Minikube stopped."

# ── 3. Clean /etc/hosts ──────────────────────────────────────────────────────
if grep -Eq '(^|[[:space:]])(pulse\.local|dev\.pulse\.local|stg\.pulse\.local)([[:space:]]|$)' /etc/hosts 2>/dev/null; then
  warn "Removing pulse host entries from /etc/hosts requires sudo."
  sudo sed -i '/pulse\.local/d;/dev\.pulse\.local/d;/stg\.pulse\.local/d' /etc/hosts
  success "/etc/hosts cleaned."
else
  info "No pulse host entries found in /etc/hosts, skipping."
fi

echo ""
success "All done."
