#!/usr/bin/env bash
set -euo pipefail

step() { echo "==> $*"; }

step "Stopping port-forwards..."
pkill -f "port-forward -n argocd" 2>/dev/null || true

step "Stopping k3s..."
sudo k3s-killall.sh

echo "==> Done."
