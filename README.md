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
./stop.sh    # tear everything down
```

Then run these in separate terminals:

```bash
minikube tunnel
kubectl port-forward -n argocd svc/argocd-server 9000:443
```

Get app URLs:

```bash
kubectl get svc pulse-api-dev pulse-api-stg pulse-api-prod
```

Use each service `EXTERNAL-IP:8080`:

| Environment | URL |
|-------------|-----|
| Dev | `http://<dev-external-ip>:8080` |
| Staging | `http://<stg-external-ip>:8080` |
| Prod | `http://<prod-external-ip>:8080` |

Argo CD dashboard → `https://localhost:9000`

Get initial Argo CD admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo
```

`start.sh` bootstraps the cluster and Argo CD. `minikube tunnel` exposes the LoadBalancer services.

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

Important: Argo CD apps in this repo track `targetRevision: HEAD` from GitHub. Local uncommitted changes are not applied to the cluster. If services still show `NodePort`, push your `LoadBalancer` changes first.

## Repo Layout

```
charts/pulse-api/    Helm chart
  values.yaml        Base values
  values-dev.yaml    Dev overrides
  values-stg.yaml    Staging overrides
  values-prod.yaml   Prod overrides
argocd/              Argo CD Application manifests
start.sh             Bring everything up
stop.sh              Tear everything down
```
