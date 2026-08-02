# k8s-playground

Deploys `pulse-api`, `otel-collector`, and `greetings-api` to a local k3s cluster across three environments (`dev`, `stg`, `prod`) using Argo CD and Helm, plus a self-hosted [SigNoz](https://signoz.io) instance as a local telemetry backend alongside New Relic.

> Linux only — the scripts rely on `systemctl` and are not compatible with macOS or Windows.

New to Kubernetes? See [docs/k8s-concepts.md](docs/k8s-concepts.md) for namespaces, pods, networking, and ports explained using this actual cluster.

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

| Environment | pulse-api | greetings-api |
|-------------|-----------|---------------|
| Dev | `http://localhost:8081` | `http://localhost:8084` |
| Staging | `http://localhost:8082` | `http://localhost:8085` |
| Prod | `http://localhost:8083` | `http://localhost:8086` |

Argo CD: `https://localhost:9000` — credentials printed by `start.sh` (username: `admin`)

SigNoz: `http://localhost:8080` — create the first account on initial login (password needs 12+ characters, upper/lowercase, a number, and a symbol)

`otel-collector` is `ClusterIP`-only (it's an internal telemetry sink other in-cluster apps send OTLP traffic to, not something a browser hits directly), so it has no host-exposed URL. It fans out to both SigNoz and New Relic in stg/prod; dev sends to SigNoz only (see `configFile` in `charts/otel-collector/values-dev.yaml`, which points at a New Relic-free config baked into the [otel-collector](https://github.com/glexposito/otel-collector) image).

SigNoz itself is installed directly via `helm upgrade --install` inside `start.sh` (idempotent, safe to rerun), not through Argo CD — it's a shared third-party backend all three `otel-collector` environments send to, not one of "this repo's" per-env apps, so it didn't fit the ApplicationSet pattern the other three use.

### Kubeconfig

`start.sh` merges k3s's kubeconfig into `~/.kube/config` instead of overwriting it, so any other cluster contexts you already have configured are preserved. The k3s cluster/user/context (normally all named `default`) is renamed to `k3s-playground` to avoid colliding with a `default` entry from another cluster, and is set as the active context. `stop.sh` does not remove this entry.

## Manual deploy with Helm

If you want to deploy without Argo CD:

```bash
helm upgrade --install pulse-api-dev  charts/pulse-api -f charts/pulse-api/values.yaml -f charts/pulse-api/values-dev.yaml
helm upgrade --install pulse-api-stg  charts/pulse-api -f charts/pulse-api/values.yaml -f charts/pulse-api/values-stg.yaml
helm upgrade --install pulse-api-prod charts/pulse-api -f charts/pulse-api/values.yaml -f charts/pulse-api/values-prod.yaml

helm upgrade --install otel-collector-dev  charts/otel-collector -f charts/otel-collector/values.yaml -f charts/otel-collector/values-dev.yaml
helm upgrade --install otel-collector-stg  charts/otel-collector -f charts/otel-collector/values.yaml -f charts/otel-collector/values-stg.yaml
helm upgrade --install otel-collector-prod charts/otel-collector -f charts/otel-collector/values.yaml -f charts/otel-collector/values-prod.yaml

helm upgrade --install greetings-api-dev  charts/greetings-api -f charts/greetings-api/values.yaml -f charts/greetings-api/values-dev.yaml
helm upgrade --install greetings-api-stg  charts/greetings-api -f charts/greetings-api/values.yaml -f charts/greetings-api/values-stg.yaml
helm upgrade --install greetings-api-prod charts/greetings-api -f charts/greetings-api/values.yaml -f charts/greetings-api/values-prod.yaml
```

`otel-collector` needs a New Relic license key at runtime. Either pass it inline (`--set newRelicLicenseKey.value=...`, fine for this local playground) or create a Secret out-of-band and point the chart at it (`--set newRelicLicenseKey.existingSecret=<secret-name>`) so the real key never lands in a values file.

`greetings-api` sends its own traces/metrics straight to `otel-collector` in the same environment's namespace (e.g. `greetings-api-dev` → `otel-collector-dev`), configured on the app side via its `appsettings.{Environment}.json` files — nothing to set on the chart side beyond `aspnetEnvironment`, which selects which of those files ASP.NET Core loads.

## Utils

```bash
./utils/hit-greetings.sh   # loops curl against /Greetings/hello and /Greetings/bye on dev/stg/prod every 10s
```

Generates steady traffic so you can watch traces/metrics show up in SigNoz/New Relic without manually curling each environment. Ctrl+C to stop.

## GitOps

Argo CD tracks `HEAD` on GitHub. Push changes to the Helm chart or values files and Argo CD syncs automatically.

## Layout

```
charts/pulse-api/       Helm chart + per-env values
charts/otel-collector/  Helm chart + per-env values
charts/greetings-api/   Helm chart + per-env values
argocd/                 Argo CD Application manifests
start.sh / stop.sh      Cluster lifecycle
utils/                  Helper scripts (traffic generation, etc.)
docs/                   Reference docs (Kubernetes concepts, etc.)
```
