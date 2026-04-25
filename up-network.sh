#!/usr/bin/env bash
set -euo pipefail

RUNTIME_DIR="/tmp/pulse-port-forward"
mkdir -p "$RUNTIME_DIR"

info() { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

for cmd in kubectl; do
  command -v "$cmd" &>/dev/null || die "$cmd not found."
done

start_pf() {
  local name="$1"
  local cmd="$2"
  local pid_file="$3"
  local log_file="$4"
  local pid

  : > "$log_file"
  (
    while true; do
      bash -lc "$cmd" >>"$log_file" 2>&1 || true
      echo "[$(date '+%F %T')] WARN: $name forward exited, restarting in 1s" >>"$log_file"
      sleep 1
    done
  ) &
  pid=$!
  echo "$pid" >"$pid_file"
  sleep 1
  if ! kill -0 "$pid" 2>/dev/null; then
    warn "$name failed to start. Check $log_file"
    return 1
  fi
  info "$name started (pid $pid)"
  return 0
}

cleanup() {
  warn "Stopping port-forwards..."
  for pid_file in "$RUNTIME_DIR"/*.pid; do
    [[ -f "$pid_file" ]] || continue
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
    rm -f "$pid_file"
  done
  info "Port-forwards stopped."
}

trap cleanup EXIT INT TERM

start_pf "dev forward" "kubectl port-forward svc/pulse-api-dev 8081:8080" \
  "$RUNTIME_DIR/dev.pid" "$RUNTIME_DIR/dev.log"
start_pf "stg forward" "kubectl port-forward svc/pulse-api-stg 8082:8080" \
  "$RUNTIME_DIR/stg.pid" "$RUNTIME_DIR/stg.log"
start_pf "prod forward" "kubectl port-forward svc/pulse-api-prod 8083:8080" \
  "$RUNTIME_DIR/prod.pid" "$RUNTIME_DIR/prod.log"
start_pf "argocd forward" "kubectl port-forward -n argocd svc/argocd-server 9000:443" \
  "$RUNTIME_DIR/argocd.pid" "$RUNTIME_DIR/argocd.log"

echo ""
info "Forwards active:"
info "  Dev:     http://localhost:8081"
info "  Staging: http://localhost:8082"
info "  Prod:    http://localhost:8083"
info "  Argo CD: https://localhost:9000"
info "Press Ctrl+C here to stop all forwards."
wait
