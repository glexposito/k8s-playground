# k8s-playground

Deploys `pulse-api` to a local Minikube cluster across three environments (`dev`, `stg`, `prod`) using Helm and Argo CD.

## Prerequisites

- `minikube`
- `kubectl`
- `helm`
- Podman (Minikube driver)

## Usage

```bash
./start.sh   # bootstrap cluster + Argo CD + apps
./up-network.sh   # keep this running for local access
./stop.sh    # tear everything down
```

Once `up-network.sh` is running, the environments are available at:

| Environment | URL |
|-------------|-----|
| Dev | http://localhost:8081 |
| Staging | http://localhost:8082 |
| Prod | http://localhost:8083 |

Argo CD dashboard → `https://localhost:9000`

`start.sh` bootstraps the cluster and Argo CD. `up-network.sh` runs and supervises the local port-forwards in one terminal.

The scripts are written for a local Linux setup using the Minikube Podman driver.

## Verification

Use these commands to confirm the cluster and apps are ready:

```bash
kubectl get pods -n argocd
kubectl get applications -n argocd
kubectl get pods,svc
```

The Argo CD applications should report `Synced` and `Healthy` before you expect the environment URLs to respond normally.

## GitOps Workflow

1. Modify the Helm chart or a values file (e.g., `values-dev.yaml`)
2. Commit and push to GitHub
3. Argo CD detects the change and syncs automatically

## Repo Layout

```
charts/pulse-api/    Helm chart
  values.yaml        Base values
  values-dev.yaml    Dev overrides
  values-stg.yaml    Staging overrides
  values-prod.yaml   Prod overrides
argocd/              Argo CD Application manifests
start.sh             Bring everything up
up-network.sh        Run all local port-forwards
stop.sh              Tear everything down
```
