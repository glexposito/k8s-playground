# k8s-playground

This repo contains a Helm chart for deploying `pulse-api` to a local Minikube cluster with three environments:

- `dev`
- `stg`
- `prod`

## Prerequisites

Install these tools before using this repo:

- `minikube`
- `kubectl`
- `helm`

You also need a running Minikube cluster with the Ingress addon enabled.

Example:

```bash
minikube start
minikube addons enable ingress
kubectl cluster-info
helm version
```

## Repo Layout

The Helm chart lives in [charts/pulse-api](./charts/pulse-api).

## Deploy

From the repo root, install or upgrade each environment:

```bash
helm upgrade --install pulse-api-dev ./charts/pulse-api -f ./charts/pulse-api/values-dev.yaml
helm upgrade --install pulse-api-stg ./charts/pulse-api -f ./charts/pulse-api/values-stg.yaml
helm upgrade --install pulse-api-prod ./charts/pulse-api -f ./charts/pulse-api/values-prod.yaml
```

Check the deployed resources:

```bash
helm list
kubectl get deploy,svc,pods
```

## Argo CD (GitOps)

This project uses Argo CD to manage deployments via GitOps.

### 1. Install Argo CD

```bash
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd --namespace argocd
```

### 2. Access Argo CD Dashboard

```bash
# Port forward to port 9000
kubectl port-forward service/argocd-server -n argocd 9000:443 &

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

Login at `https://localhost:9000` with username `admin`.

### 3. Register Applications

Apply the application manifests to register the environments with Argo CD:

```bash
kubectl apply -f argocd/
```

## Local DNS Setup

To access the environments via hostnames, add the following to your `/etc/hosts` file:

```bash
echo "$(minikube ip) pulse.local dev.pulse.local stg.pulse.local" | sudo tee -a /etc/hosts
```

## Access The Environments

Once the Ingress is active and your hosts file is updated, you can access the environments directly via their hostnames:

- **Prod**: [http://pulse.local](http://pulse.local)
- **Staging**: [http://stg.pulse.local](http://stg.pulse.local)
- **Dev**: [http://dev.pulse.local](http://dev.pulse.local)

*(Note: No port-forwarding is required for the applications anymore!)*

## GitOps Workflow

To redeploy or change any environment:
1. Modify the Helm chart or environment values (e.g., `values-dev.yaml`).
2. Commit and push changes to GitHub.
3. Argo CD will automatically detect the changes and sync the cluster.

## Clean Up

Remove the Helm releases:

```bash
helm uninstall pulse-api-dev
helm uninstall pulse-api-stg
helm uninstall pulse-api-prod
```

Verify cleanup:

```bash
helm list
kubectl get deploy,svc,pods
```

## Notes

- The base chart values are in [charts/pulse-api/values.yaml](./charts/pulse-api/values.yaml).
- Environment-specific overrides are in:
  - [charts/pulse-api/values-dev.yaml](./charts/pulse-api/values-dev.yaml)
  - [charts/pulse-api/values-stg.yaml](./charts/pulse-api/values-stg.yaml)
  - [charts/pulse-api/values-prod.yaml](./charts/pulse-api/values-prod.yaml)
- The chart currently uses the `latest` image tag.
