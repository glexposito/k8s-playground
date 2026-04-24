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

You also need a running Minikube cluster.

Example:

```bash
minikube start
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

## Access The Environments

All environments use `ClusterIP`, so access them with `kubectl port-forward`.

Run one command per terminal:

```bash
kubectl port-forward service/pulse-api-dev 8080:8080 &
kubectl port-forward service/pulse-api-stg 8081:8080 &
kubectl port-forward service/pulse-api-prod 8082:8080 &
```

Then open:

- `dev`: `http://localhost:8080`
- `stg`: `http://localhost:8081`
- `prod`: `http://localhost:8082`

You can also test health endpoints:

- `http://localhost:8080/ready`
- `http://localhost:8081/ready`
- `http://localhost:8082/ready`

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
