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
RUNTIME_DIR="/tmp/pulse-api-runtime"
TUNNEL_LOG="$RUNTIME_DIR/minikube-tunnel.log"
TUNNEL_SUPERVISOR_PID_FILE="$RUNTIME_DIR/minikube-tunnel-supervisor.pid"

info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }
warn()    { echo "[WARN]  $*"; }
die()     { echo "[ERROR] $*" >&2; exit 1; }

stop_supervisor_if_running() {
  local pid_file="$1"
  local name="$2"
  local pid

  if [[ ! -f "$pid_file" ]]; then
    return 0
  fi

  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    success "Stopped existing $name supervisor."
  fi
  rm -f "$pid_file"
}

wait_for_tunnel() {
  local pid="$1"
  local log_file="$2"
  local i

  # minikube tunnel output can be sparse/buffered when redirected to a file.
  # Treat a stable running process as "ready" unless we detect a hard error.
  for i in {1..20}; do
    if ! kill -0 "$pid" 2>/dev/null; then
      if [[ -f "$log_file" ]] && [[ -s "$log_file" ]]; then
        sed 's/^/[ERROR] /' "$log_file" >&2
      fi
      die "Minikube tunnel failed to start."
    fi

    if [[ -f "$log_file" ]] && grep -Eqi "permission denied|fatal|error:|no such container|unable to get control-plane node" "$log_file"; then
      sed 's/^/[ERROR] /' "$log_file" >&2
      die "Minikube tunnel reported an error."
    fi

    if (( i >= 5 )); then
      success "Minikube tunnel ready."
      return 0
    fi

    sleep 1
  done

  kill "$pid" 2>/dev/null || true
  die "Minikube tunnel did not become ready in time."
}

start_tunnel_supervisor() {
  local log_file="$1"
  local pid_file="$2"
  local supervisor_pid

  : > "$log_file"
  (
    while true; do
      minikube tunnel >> "$log_file" 2>&1 || true
      echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') minikube tunnel exited; retrying in 2s." >> "$log_file"
      sleep 2
    done
  ) &
  supervisor_pid=$!
  echo "$supervisor_pid" > "$pid_file"
  wait_for_tunnel "$supervisor_pid" "$log_file"
}

# ── 1. Check dependencies ────────────────────────────────────────────────────
info "Checking required tools..."
for cmd in minikube kubectl helm podman; do
  command -v "$cmd" &>/dev/null || die "$cmd not found. Install it before running this script."
done
success "All required tools found."
mkdir -p "$RUNTIME_DIR"

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

# ── 8. Minikube tunnel ───────────────────────────────────────────────────────
info "Starting self-healing minikube tunnel supervisor..."
stop_supervisor_if_running "$TUNNEL_SUPERVISOR_PID_FILE" "Minikube tunnel"
pkill -f "minikube tunnel" 2>/dev/null || true
pkill -f "port-forward.*ingress-nginx-controller" 2>/dev/null || true
pkill -f "port-forward.*argocd-server" 2>/dev/null || true
start_tunnel_supervisor "$TUNNEL_LOG" "$TUNNEL_SUPERVISOR_PID_FILE"

# ── 9. Summary ───────────────────────────────────────────────────────────────
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "<secret not found>")
echo ""
success "Bootstrap complete. Argo CD is syncing the applications now:"
echo "  Prod    → http://pulse.local"
echo "  Staging → http://stg.pulse.local"
echo "  Dev     → http://dev.pulse.local"
echo ""
info "Argo CD dashboard (optional local forward):"
info "  kubectl port-forward -n argocd svc/argocd-server 9000:443"
info "  then open https://localhost:9000"
info "  Username: admin"
info "  Password: $ARGOCD_PASSWORD"
echo ""
warn "The URLs may return errors until Argo CD finishes syncing and the pods become ready."
info "Tunnel log:"
info "  $TUNNEL_LOG"
info "If tunnel fails, run manually in another terminal:"
info "  minikube tunnel"
info "To tear down: ./stop.sh"
