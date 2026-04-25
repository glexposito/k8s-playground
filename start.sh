#!/usr/bin/env bash
# Tested on Arch Linux.
#
# Requirements:
#   minikube   https://minikube.sigs.k8s.io/docs/start/
#   kubectl    https://kubernetes.io/docs/tasks/tools/
#   helm       https://helm.sh/docs/intro/install/
#   podman     https://podman.io/docs/installation
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTS_LINE="127.0.0.1 pulse.local dev.pulse.local stg.pulse.local"

info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }
warn()    { echo "[WARN]  $*"; }
die()     { echo "[ERROR] $*" >&2; exit 1; }

wait_for_port_forward() {
  local pid="$1"
  local log_file="$2"
  local name="$3"
  local i

  for i in {1..20}; do
    if ! kill -0 "$pid" 2>/dev/null; then
      if [[ -f "$log_file" ]] && [[ -s "$log_file" ]]; then
        sed 's/^/[ERROR] /' "$log_file" >&2
      fi
      die "$name port-forward failed to start."
    fi

    if [[ -f "$log_file" ]] && grep -q "Forwarding from" "$log_file"; then
      success "$name port-forward ready."
      return 0
    fi

    sleep 1
  done

  kill "$pid" 2>/dev/null || true
  die "$name port-forward did not become ready in time."
}

# ── 1. Check dependencies ────────────────────────────────────────────────────
info "Checking required tools..."
for cmd in minikube kubectl helm podman; do
  command -v "$cmd" &>/dev/null || die "$cmd not found. Install it before running this script."
done
success "All required tools found."

# ── 2. Start Minikube ────────────────────────────────────────────────────────
info "Starting Minikube with Podman driver and containerd runtime..."
minikube start --driver=podman --container-runtime=containerd
success "Minikube started."

# ── 3. Enable Ingress addon ──────────────────────────────────────────────────
info "Enabling Ingress addon..."
minikube addons enable ingress
success "Ingress addon enabled."

# ── 4. Install Argo CD ───────────────────────────────────────────────────────
info "Installing Argo CD..."
kubectl get namespace argocd &>/dev/null || kubectl create namespace argocd
if kubectl get deployment argocd-server -n argocd &>/dev/null; then
  info "Argo CD already running, skipping install."
else
  helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
  helm repo update argo
  helm install argocd argo/argo-cd --namespace argocd
  success "Argo CD installed."
fi

# ── 5. Wait for Argo CD server ───────────────────────────────────────────────
info "Waiting for Argo CD server to be ready (this may take a minute)..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s
success "Argo CD server ready."

# ── 6. Register applications ─────────────────────────────────────────────────
info "Registering Argo CD applications..."
kubectl apply -f "$REPO_ROOT/argocd/"
success "Applications registered. Argo CD will sync dev/stg/prod from GitHub."

# ── 7. /etc/hosts ────────────────────────────────────────────────────────────
if grep -qF "$HOSTS_LINE" /etc/hosts 2>/dev/null; then
  success "/etc/hosts already has the required entries, skipping."
else
  warn "About to write to /etc/hosts (requires sudo)."
  warn "  WHY: Ingress uses hostname-based routing. Without these entries your"
  warn "  browser will not resolve pulse.local / dev.pulse.local / stg.pulse.local."
  echo -n "  Proceed? [y/N] "
  read -r answer
  if [[ "${answer,,}" == "y" ]]; then
    echo "$HOSTS_LINE" | sudo tee -a /etc/hosts > /dev/null
    success "/etc/hosts updated."
  else
    warn "Skipped /etc/hosts update. Hostnames will not resolve until you add them manually."
  fi
fi

# ── 8. Port-forwards ─────────────────────────────────────────────────────────
info "Starting port-forwards..."
pkill -f "port-forward.*ingress-nginx-controller" 2>/dev/null || true
pkill -f "port-forward.*argocd-server" 2>/dev/null || true
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80 \
  > /tmp/ingress-portforward.log 2>&1 &
INGRESS_PF_PID=$!
kubectl port-forward -n argocd svc/argocd-server 9000:443 \
  > /tmp/argocd-portforward.log 2>&1 &
ARGOCD_PF_PID=$!
wait_for_port_forward "$INGRESS_PF_PID" /tmp/ingress-portforward.log "Ingress"
wait_for_port_forward "$ARGOCD_PF_PID" /tmp/argocd-portforward.log "Argo CD"

# ── 9. Summary ───────────────────────────────────────────────────────────────
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "<secret not found>")
echo ""
success "Bootstrap complete. Argo CD is syncing the applications now:"
echo "  Prod    → http://pulse.local:8080"
echo "  Staging → http://stg.pulse.local:8080"
echo "  Dev     → http://dev.pulse.local:8080"
echo ""
info "Argo CD dashboard → https://localhost:9000"
info "  Username: admin"
info "  Password: $ARGOCD_PASSWORD"
echo ""
warn "The URLs may return errors until Argo CD finishes syncing and the pods become ready."
info "To tear down: ./stop.sh"
