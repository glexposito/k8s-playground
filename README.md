# k8s-playground

Deploys `pulse-api` to a local Minikube cluster across three environments (`dev`, `stg`, `prod`) using Helm and Argo CD.

## Prerequisites

- `minikube`
- `kubectl`
- `helm`
- Podman (Minikube driver)

## Usage

```bash
./start.sh   # bring everything up
./stop.sh    # tear everything down
```

Once Argo CD finishes syncing and the pods are ready, the environments are available at:

| Environment | URL |
|-------------|-----|
| Prod | http://pulse.local:8080 |
| Staging | http://stg.pulse.local:8080 |
| Dev | http://dev.pulse.local:8080 |

Argo CD dashboard → `https://localhost:9000` (credentials printed by `start.sh`)

`start.sh` verifies that the port-forwards are up before it exits, but the application URLs may still return errors briefly while Argo CD syncs the chart and the pods become ready.

The scripts are written for a local Linux setup using the Minikube Podman driver.

When approved, `start.sh` adds `pulse.local`, `dev.pulse.local`, and `stg.pulse.local` to `/etc/hosts` with `sudo`. `stop.sh` removes those entries.

## Verification

Use these commands to confirm the cluster and apps are ready:

```bash
kubectl get pods -n argocd
kubectl get applications -n argocd
kubectl get pods,svc,ingress
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
stop.sh              Tear everything down
```
