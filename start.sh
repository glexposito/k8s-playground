#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

step() { echo "==> $*"; }

step "Starting k3s..."
if ! systemctl is-active --quiet k3s; then
  sudo systemctl start k3s
fi

step "Merging k3s kubeconfig into ~/.kube/config..."
mkdir -p ~/.kube
touch ~/.kube/config
K3S_KUBECONFIG="$(mktemp)"
trap 'rm -f "$K3S_KUBECONFIG"' EXIT
# k3s.yaml names its cluster/user/context "default"; rename to avoid
# clobbering an existing "default" entry from another cluster on merge.
sudo sed 's/\bdefault\b/k3s-playground/g' /etc/rancher/k3s/k3s.yaml > "$K3S_KUBECONFIG"
KUBECONFIG="$K3S_KUBECONFIG:$HOME/.kube/config" kubectl config view --flatten > "${K3S_KUBECONFIG}.merged"
mv "${K3S_KUBECONFIG}.merged" "$HOME/.kube/config"
export KUBECONFIG="$HOME/.kube/config"
kubectl config use-context k3s-playground
kubectl wait --for=condition=ready node --all --timeout=60s

step "Installing Argo CD..."
kubectl create namespace argocd 2>/dev/null || true
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s

step "Installing SigNoz..."
# https://signoz.io/docs/install/kubernetes/local/?k8s-distro=k3s
helm repo add signoz https://charts.signoz.io >/dev/null
helm repo update signoz >/dev/null
helm upgrade --install signoz signoz/signoz -n signoz --create-namespace >/dev/null

step "Registering apps with Argo CD..."
kubectl apply -f "$REPO_ROOT/argocd/"

step "Exposing Argo CD and SigNoz..."
if pgrep -f "port-forward -n argocd svc/argocd-server" > /dev/null; then
  echo "Argo CD port-forward already running."
else
  kubectl port-forward -n argocd svc/argocd-server 9000:443 &>/dev/null &
  disown
fi

if pgrep -f "port-forward -n signoz svc/signoz " > /dev/null; then
  echo "SigNoz port-forward already running."
else
  kubectl port-forward -n signoz svc/signoz 8080:8080 &>/dev/null &
  disown
fi

ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "Pulse dev:       http://localhost:8081"
echo "Pulse stg:       http://localhost:8082"
echo "Pulse prod:      http://localhost:8083"
echo "Greetings dev:   http://localhost:8084"
echo "Greetings stg:   http://localhost:8085"
echo "Greetings prod:  http://localhost:8086"
echo "Argo CD:         https://localhost:9000  (admin / $ARGOCD_PASS)"
echo "SigNoz:          http://localhost:8080"
