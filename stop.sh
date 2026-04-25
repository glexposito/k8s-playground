#!/usr/bin/env bash
set -euo pipefail

HOSTS=(pulse.local dev.pulse.local stg.pulse.local)

info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }
warn()    { echo "[WARN]  $*"; }

# ── 1. Kill port-forwards ────────────────────────────────────────────────────
pkill -f "port-forward.*ingress-nginx-controller" 2>/dev/null && success "Ingress port-forward stopped." || info "No ingress port-forward running."
pkill -f "port-forward.*argocd-server"            2>/dev/null && success "Argo CD port-forward stopped." || info "No Argo CD port-forward running."

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
