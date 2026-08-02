# Kubernetes concepts, explained through this cluster

Kubernetes jargon is easy to half-remember — pod vs. node vs. namespace vs. cluster blur together fast if you're not touching it every week. This doc exists so anyone (future you included) can look something up in under a minute instead of re-deriving it from scratch.

Every example below uses real names/ports from this actual cluster, verified with `kubectl` — check with the commands shown any time something seems out of date.

## Control plane vs. worker nodes ("the brain" and "the muscle")

A Kubernetes cluster is normally split into two kinds of machines:

- **Control plane** (the brain) — runs the API server (everything, including `kubectl`, talks to it), the scheduler (decides which node a pod runs on), and etcd (the database holding all cluster state: every Deployment, Service, Secret). It makes decisions; it doesn't run your apps.
- **Worker nodes** (the muscle) — run your actual containers (pods). A worker doesn't know what the whole cluster looks like; it just does what the control plane tells it.

In production these are usually separate machines (often 3 control-plane nodes for redundancy, plus any number of workers), so losing an app doesn't take down cluster management, and vice versa.

**k3s collapses this to one machine.** Check yours:

```bash
kubectl get nodes
# NAME     STATUS   ROLES           AGE   VERSION
# mother   Ready    control-plane   14h   v1.35.6+k3s1
```

One node (`mother`) does both jobs at once. That's fine for local dev; it's not how you'd run this for anything with real uptime requirements.

## Namespaces

A namespace is a logical folder inside one cluster — not a separate cluster, network, or machine. It's there to avoid name collisions and group related things. Two objects can share the exact same name if they're in different namespaces.

```bash
kubectl get namespaces
```

This cluster uses one namespace per app *and* environment — a choice made in this repo, not a Kubernetes requirement:

```
pulse-api-dev, pulse-api-stg, pulse-api-prod
otel-collector-dev, otel-collector-stg, otel-collector-prod
greetings-api-dev, greetings-api-stg, greetings-api-prod
signoz
argocd
```

That's why `pulse-api-dev` and `pulse-api-prod` can each have a Deployment literally named `pulse-api` without conflicting — different namespaces.

## Pods

The smallest thing Kubernetes actually schedules and runs. A pod wraps one or more containers that always run together on the same node, sharing one network address.

```bash
kubectl get pods -n otel-collector-dev
# otel-collector-dev-855bdfc47c-pht2r   1/1   Running
```

You never create a pod directly in this repo — you create a **Deployment** (`charts/*/templates/deployment.yaml`), and the Deployment creates and manages pods for you: if one crashes, it creates a replacement automatically. The random suffix (`-855bdfc47c-pht2r`) is how Kubernetes names each generation of pod uniquely.

**One container per pod, every time, in this repo.** Kubernetes allows multiple containers in one pod — the "sidecar" pattern, for a helper process that needs to share the main container's network/filesystem (e.g. a log shipper or proxy). But every `templates/deployment.yaml` in this repo defines exactly one container, so here "pod" and "container" mean the same thing in practice:

```bash
kubectl get pods -n greetings-api-dev -o jsonpath='{range .items[*]}{.metadata.name}{": "}{range .spec.containers[*]}{.name}{" "}{end}{"\n"}{end}'
# greetings-api-dev-547fd96855-klzl8: greetings-api
```

This isn't automatic or enforced by Kubernetes — it's simply what's written in each `deployment.yaml`'s `containers:` list. Nothing stops you from adding a second container there; nothing in this repo has needed one yet.

## Networking — is a port "per cluster"?

No — there's no cluster-wide port. Ports belong to whatever is actually listening: a container, a Service, or (in specific cases) a node. Three unrelated "port" concepts show up in this repo's charts, and mixing them up is the most common source of confusion:

| Concept | Example from this repo | What it means |
|---|---|---|
| `containerPort` | `8080` (pulse-api, greetings-api) | The port the app process inside the container binds to. Decided by the app's own code. |
| `service.port` (Service) | `8081`/`8082`/`8083` (pulse-api dev/stg/prod) | The port other things use to reach the Service. Kubernetes forwards traffic from here to the pod's `containerPort` — they don't have to match. |
| Host port | `localhost:8081` on your PC | Only exists for `LoadBalancer`/`NodePort` Services. k3s's built-in `ServiceLB` binds the Service port directly onto your machine's network. |

`otel-collector` is `ClusterIP`-only (no `LoadBalancer`), so it has **no host port at all** — `localhost:4317` means nothing on your PC. It's only reachable from inside the cluster (via its Service DNS name, below) or through a temporary `kubectl port-forward` tunnel.

Think of your PC and the cluster as two separate private networks sharing one physical machine — same idea as Docker containers each getting their own network namespace. `LoadBalancer` is what deliberately bridges the two.

## Cluster-internal DNS (how pods find each other)

Every Service automatically gets a DNS name, no configuration needed:

```
<service-name>.<namespace>.svc.cluster.local
```

Verified working right now, from inside this cluster:

```bash
otel-collector-dev.otel-collector-dev.svc.cluster.local:4317
signoz-otel-collector.signoz.svc.cluster.local:4317
```

This is how `greetings-api` sends telemetry to `otel-collector`, and how `otel-collector` forwards it to `signoz` — pod-to-pod, entirely inside the cluster's private network, never touching your PC or the internet. CoreDNS (a pod in `kube-system`) resolves these names automatically.

## Ingress controller

Not used in this repo, but worth knowing since it's the standard alternative to what this repo does instead.

Right now, every app that needs host access gets its own `LoadBalancer` Service with its own port (`pulse-api-dev` → `8081`, `greetings-api-dev` → `8084`, etc.) — one port per app per environment to remember.

An **Ingress controller** (e.g. nginx-ingress, or Traefik — which k3s ships by default, though this repo doesn't use it) is a single shared entry point instead: one exposed port (`80`/`443`), routing incoming requests to the right internal Service by hostname or path (`pulse.local` → `pulse-api-dev`). An Ingress *resource* just declares routing rules; the Ingress *controller* is the pod that actually does the routing. This is the more common pattern once you have more than a couple of exposed apps, since it doesn't need a new host port per service.

Traefik is genuinely running in this cluster right now, just unused:

```bash
kubectl get pods -n kube-system | grep traefik
```

## Deployments and ReplicaSets — how "keep N copies running" works

A **Deployment** (what every chart's `templates/deployment.yaml` defines) describes desired state: "I want `replicaCount` copies of this pod running, using this image." Kubernetes continuously works to make reality match that — if a pod dies, a new one gets created; if you change the image or an env var, old pods get replaced with new ones (a "rollout").

**Each replica is its own separate pod** — not multiple copies bundled into one. `replicaCount: 2` means two independent pods, each with its own IP, each individually replaceable if it crashes:

```bash
kubectl get deployments -n greetings-api-prod
kubectl get replicasets -n greetings-api-prod
kubectl get pods -n greetings-api-prod
# greetings-api-547fd96855-abc12   1/1   Running
# greetings-api-547fd96855-xyz34   1/1   Running
```

Under the hood a Deployment manages a **ReplicaSet**, which manages the actual pods — you'll rarely touch ReplicaSets directly; the Deployment is what you read/edit.

## Secrets — how `nr-license` was added

A **Secret** holds sensitive values (API keys, passwords, tokens) so they can be injected into a pod as an env var or file, without hardcoding them into a Deployment's YAML. Important nuance: a Secret is only **base64-encoded, not encrypted** — anyone with `kubectl get secret -o yaml` access to that namespace can trivially decode it. It keeps secrets out of your manifests and git history; it isn't real encryption at rest (this cluster doesn't have that configured separately).

Secrets are also **namespace-scoped**, same as pods — one created in `otel-collector-dev` doesn't exist in `otel-collector-stg`, even with an identical name. That's why `nr-license` had to be created three times, once per namespace:

```bash
kubectl create secret generic nr-license \
  --from-literal=license-key='<the-real-new-relic-key>' \
  -n otel-collector-dev
```

(repeated for `otel-collector-stg` and `otel-collector-prod`)

It was never written into any file in this repo, and never committed to git — created directly against the live cluster, out-of-band. The chart only needs to know **the name** of a Secret to look for, which is safe to commit since it reveals nothing sensitive:

```yaml
# charts/otel-collector/values-stg.yaml
newRelicLicenseKey:
  existingSecret: nr-license
```

`templates/deployment.yaml` wires that name into the pod's env var via `secretKeyRef` — Kubernetes resolves the actual value at pod-start time, straight from the Secret object, never from git:

```yaml
- name: NEW_RELIC_LICENSE_KEY
  valueFrom:
    secretKeyRef:
      name: nr-license
      key: license-key
```

Gotcha worth remembering: updating a Secret doesn't automatically update pods already running — they only read it once, at creation. A Secret change always needs a follow-up `kubectl rollout restart deployment/<name> -n <namespace>` to take effect.

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

`kubectl get pods -A` is the best starting point if you're unsure what's running — no flag defaults to your current namespace context (usually `default`), which is almost always the wrong scope here, since nothing in this repo runs in `default`.

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
