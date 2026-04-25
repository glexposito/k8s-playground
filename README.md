# k8s-playground

Deploys `pulse-api` to a local k3s cluster across three environments (`dev`, `stg`, `prod`) using Argo CD and Helm.

## Prerequisites

- `k3s`
- `kubectl`
- `helm` (optional — only needed if deploying manually without Argo CD)
- `k9s` (optional — terminal UI for cluster monitoring)

## Usage

```bash
./start.sh   # start cluster + deploy Argo CD + apps
./stop.sh    # stop cluster
```

| Environment | URL |
|-------------|-----|
| Dev | `http://localhost:8081` |
| Staging | `http://localhost:8082` |
| Prod | `http://localhost:8083` |

Argo CD: `https://localhost:9000` — credentials printed by `start.sh` (username: `admin`)

## Manual deploy with Helm

If you want to deploy without Argo CD:

```bash
helm upgrade --install pulse-api-dev  charts/pulse-api -f charts/pulse-api/values.yaml -f charts/pulse-api/values-dev.yaml
helm upgrade --install pulse-api-stg  charts/pulse-api -f charts/pulse-api/values.yaml -f charts/pulse-api/values-stg.yaml
helm upgrade --install pulse-api-prod charts/pulse-api -f charts/pulse-api/values.yaml -f charts/pulse-api/values-prod.yaml
```

## GitOps

Argo CD tracks `HEAD` on GitHub. Push changes to the Helm chart or values files and Argo CD syncs automatically.

## Layout

```
charts/pulse-api/    Helm chart + per-env values
argocd/              Argo CD Application manifests
start.sh / stop.sh   Cluster lifecycle
```
