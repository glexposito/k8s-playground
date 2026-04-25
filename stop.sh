#!/usr/bin/env bash
set -euo pipefail

pkill -f "port-forward -n argocd" 2>/dev/null || true
sudo systemctl stop k3s
