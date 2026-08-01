# Kubernetes concepts, explained through this cluster

Kubernetes has a lot of jargon that's easy to half-remember and forget again if you're not touching it every week — pod vs. node vs. namespace vs. cluster all blur together fast. Nobody's brain reliably holds onto vocabulary it doesn't use regularly, and that's fine. This doc exists so anyone (future you included) can look something up in under a minute instead of re-deriving it from scratch or feeling bad for forgetting.

Every example below uses real names/ports from this actual cluster (verified with `kubectl`), not generic placeholders — check with the commands shown any time something seems out of date.

## The control plane vs. worker nodes ("the brain")

A Kubernetes cluster is normally split into two kinds of machines:

- **Control plane** — the "brain." Runs the API server (everything, including `kubectl`, talks to it), the scheduler (decides which node a pod runs on), and etcd (the database storing all cluster state — every Deployment, Service, Secret, everything). It makes decisions; it doesn't run your apps.
- **Worker nodes** — the "muscle." Run your actual containers (pods). A worker has no idea what the whole cluster looks like — it just does what the control plane tells it to.

In a real production setup these are usually separate machines (often 3 control-plane nodes for redundancy, plus any number of worker nodes), so losing an app doesn't take down cluster management, and vice versa.

**k3s collapses this to one machine** — check yours:

```bash
kubectl get nodes
# NAME     STATUS   ROLES           AGE   VERSION
# mother   Ready    control-plane   14h   v1.35.6+k3s1
```

One node (`mother`), doing both jobs — it's both "the brain" and "the muscle" at once. That's fine for local dev/playground use; it's just not how you'd run this for anything with real uptime requirements.

## Namespaces

A namespace is **not** a separate cluster, a separate network, or a separate machine — it's a logical folder inside one single cluster, used to avoid name collisions and to group related things. Two objects can share the exact same name if they're in different namespaces.

```bash
kubectl get namespaces
```

This cluster uses one namespace per app *and* environment — that's a deliberate choice made in this repo, not a Kubernetes requirement:

```
pulse-api-dev, pulse-api-stg, pulse-api-prod
otel-collector-dev, otel-collector-stg, otel-collector-prod
greetings-api-dev, greetings-api-stg, greetings-api-prod
signoz
argocd
```

This is *why* `pulse-api-dev` and `pulse-api-prod` can both have a Deployment literally named `pulse-api` without conflicting — they're in different namespaces.

## Pods

The smallest thing Kubernetes actually schedules and runs. A pod wraps one or more containers that always run together on the same node, sharing the same network address. In this cluster, it's almost always **one container per pod** (simplest, most common case).

```bash
kubectl get pods -n otel-collector-dev
# otel-collector-dev-855bdfc47c-pht2r   1/1   Running
```

You never create a pod directly in this repo — you create a **Deployment** (see `charts/*/templates/deployment.yaml`), and the Deployment creates and manages pods for you: if one crashes, the Deployment notices and creates a replacement automatically. The random suffix (`-855bdfc47c-pht2r`) is Kubernetes' way of naming each generation of pod uniquely.

### Is a pod just "any" container?

Not quite — a pod isn't an arbitrary grouping. Containers only belong in the same pod if they genuinely need to run **tightly coupled**: sharing the same IP address (they can reach each other via `localhost`), optionally sharing storage volumes, and always scheduled onto the same node together, living and dying as one unit.

In practice, one container per pod is the overwhelmingly common case — and it's the *only* case anywhere in this cluster. Check any pod here:

```bash
kubectl get pods -n greetings-api-dev -o jsonpath='{range .items[*]}{.metadata.name}{": "}{range .spec.containers[*]}{.name}{" "}{end}{"\n"}{end}'
# greetings-api-dev-547fd96855-klzl8: greetings-api
```

One pod, one container, same name pattern every time.

Multi-container pods *do* exist — the "sidecar" pattern, where a small helper container rides alongside the main app container in the same pod specifically to share its network/filesystem (e.g. a logging agent that reads log files the main container writes, or a proxy that intercepts the main container's traffic). None of the charts in this repo use that pattern; every `templates/deployment.yaml` here defines exactly one container. So for this repo specifically, "pod" and "container" are effectively interchangeable in practice, even though Kubernetes technically allows more.

## Networking — is a port "per cluster"?

No — there's no such thing as a cluster-wide port. Ports belong to whatever is actually listening: a container, a Service, or (in specific cases) a node. Three different, unrelated "port" concepts show up in this repo's charts, and mixing them up is the single most common source of confusion:

| Concept | Example from this repo | What it means |
|---|---|---|
| `containerPort` | `8080` (pulse-api, greetings-api) | The port the actual app process inside the container binds to. Decided by the app's own code. |
| `service.port` (Service) | `8081`/`8082`/`8083` (pulse-api dev/stg/prod) | The port other things use to reach the Service. Kubernetes forwards traffic from here to the pod's `containerPort` — they don't have to match. |
| Host port | `localhost:8081` on your PC | Only exists for `LoadBalancer`/`NodePort` Services. k3s's built-in `ServiceLB` binds the Service port directly onto your real machine's network. |

`otel-collector` is `ClusterIP`-only (no `LoadBalancer`), so it has **no host port at all** — `localhost:4317` means nothing on your PC. It's only reachable from *inside* the cluster, via its Service DNS name (see below), or through a temporary `kubectl port-forward` tunnel.

Think of your PC and the cluster as two separate private networks that happen to run on the same physical machine (same idea as Docker containers each getting their own network namespace). `LoadBalancer` is the one thing that deliberately bridges the two.

## Cluster-internal DNS (how pods find each other)

Every Service automatically gets a DNS name, with zero configuration needed:

```
<service-name>.<namespace>.svc.cluster.local
```

Verified working right now, from inside this cluster:

```bash
otel-collector-dev.otel-collector-dev.svc.cluster.local:4317
signoz-otel-collector.signoz.svc.cluster.local:4317
```

This is how `greetings-api` sends telemetry to `otel-collector`, and how `otel-collector` sends it on to `signoz` — pod-to-pod, entirely inside the cluster's private network, never touching your PC or the internet. CoreDNS (a pod running in `kube-system`) is what resolves these names; it's installed automatically, nothing you configure.

## Ingress controller

Not currently used in this repo — worth knowing what it *is*, though, since it's the more standard alternative to what this repo does instead.

Right now, every app that needs host access gets its own `LoadBalancer` Service with its own unique port (`pulse-api-dev` → `8081`, `greetings-api-dev` → `8084`, etc.) — one port per app per environment, and you have to remember which is which.

An **Ingress controller** (e.g. nginx-ingress, Traefik — k3s actually ships Traefik by default, though this repo doesn't use it) is a single shared entry point instead: one exposed port (typically `80`/`443`), and it routes incoming requests to the right internal Service based on the hostname or URL path (`pulse.local` → `pulse-api-dev`, `greetings.local` → `greetings-api-dev`, etc.). It's an extra layer — an Ingress *resource* just declares routing rules; the Ingress *controller* is the actual pod doing the routing work. This is the more common pattern for anything with more than a couple of exposed apps, since it doesn't require a new host port for every single service.

That default Traefik install is genuinely running in this cluster right now, just unused — see for yourself:

```bash
kubectl get pods -n kube-system | grep traefik
```

## Try it yourself — useful commands to explore this cluster

```bash
kubectl get pods -A                              # every pod, every namespace, one shot
kubectl get namespaces                           # every namespace that exists
kubectl get svc -A                                # every Service (see the ClusterIP vs LoadBalancer split)
kubectl get nodes -o wide                         # the (single) node, and its role
kubectl get deployments -A                        # every Deployment, across every app/env
kubectl describe pod <pod-name> -n <namespace>    # full detail on one pod: image, env vars, events, why it's (not) healthy
kubectl logs <pod-name> -n <namespace>            # what that pod has printed
kubectl exec -it <pod-name> -n <namespace> -- sh  # get an interactive shell inside a running container (if it has one)
```

`kubectl get pods -A` is the best starting point if you're ever unsure what's actually running — no flag defaults to just your current namespace context (usually `default`), which is almost always the wrong scope to look at here, since nothing in this repo actually runs in `default`.

## Deployments, ReplicaSets — how "keep N copies running" works

A **Deployment** (what every chart in `charts/*/templates/deployment.yaml` defines) describes desired state: "I want `replicaCount` copies of this pod running, using this image." Kubernetes continuously works to make reality match that — if a pod dies, a new one gets created; if you change the image or an env var, old pods get replaced with new ones (a "rollout").

Under the hood a Deployment manages a **ReplicaSet** (which manages the actual pods) — you'll rarely interact with ReplicaSets directly, the Deployment is the thing you actually read/edit.

```bash
kubectl get deployments -n greetings-api-prod
kubectl get replicasets -n greetings-api-prod
```

## Secrets — how `nr-license` was added

A **Secret** is a Kubernetes object for holding sensitive values (API keys, passwords, tokens) so they can be injected into a pod as an env var or file, without hardcoding them into a Deployment's YAML. Important nuance: a Secret is only **base64-encoded**, not encrypted — anyone with `kubectl get secret -o yaml` access to that namespace can trivially decode it. It's a convention for keeping secrets out of your manifests/git history, not real encryption at rest (unless your cluster has that separately configured, which this one doesn't).

Secrets are also **namespace-scoped**, same as pods — a Secret created in `otel-collector-dev` doesn't exist in `otel-collector-stg`, even with the identical name. That's why `nr-license` had to be created three separate times, once per namespace:

```bash
kubectl create secret generic nr-license \
  --from-literal=license-key='<the-real-new-relic-key>' \
  -n otel-collector-dev
```

(repeated for `otel-collector-stg` and `otel-collector-prod`)

It was never written into any file in this repo, and never committed to git — created directly against the live cluster, out-of-band. The chart just needed to know **the name** of a Secret to look for, which is safe to commit since it reveals nothing sensitive:

```yaml
# charts/otel-collector/values-stg.yaml
newRelicLicenseKey:
  existingSecret: nr-license
```

`templates/deployment.yaml` then wires that name into the pod's env var via a `secretKeyRef` — Kubernetes resolves the actual value at pod-start time, pulling it straight from the Secret object, never from anything in git:

```yaml
- name: NEW_RELIC_LICENSE_KEY
  valueFrom:
    secretKeyRef:
      name: nr-license
      key: license-key
```

One gotcha worth remembering: updating a Secret's value doesn't automatically update pods that are already running — they only read it once, at pod creation. Changing a Secret always needs a follow-up `kubectl rollout restart deployment/<name> -n <namespace>` to actually take effect.

## Quick map: this repo's concepts → Kubernetes concepts

| This repo | Kubernetes concept |
|---|---|
| `charts/*/templates/deployment.yaml` | Deployment (+ the ReplicaSet/pods it manages) |
| `charts/*/templates/service.yaml` | Service (`ClusterIP` or `LoadBalancer`) |
| `otel-collector-dev`, `pulse-api-prod`, etc. | Namespaces |
| `nr-license` (created manually via `kubectl create secret`) | Secret |
| the single `mother` node | Control plane + worker, combined (k3s-specific) |
| `otel-collector-dev.otel-collector-dev.svc.cluster.local` | Cluster-internal DNS, via CoreDNS |
| *(not used in this repo)* | Ingress / Ingress controller |
