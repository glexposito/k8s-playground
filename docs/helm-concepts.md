# Helm, explained through `charts/otel-collector`

Same idea as [k8s-concepts.md](k8s-concepts.md): real files from this repo, not generic examples. This one walks through `charts/otel-collector/templates/deployment.yaml` line by line and explains what problem each piece is actually solving — including being honest about which parts `kubectl` alone could already do, so Helm doesn't feel like magic you have to trust blindly.

## What is Helm?

Helm is a **package manager for Kubernetes** — same idea as `apt`/`npm`/`nuget`, applied to Kubernetes resources instead of OS packages or code libraries. A "package" in Helm terms is called a **chart**: a directory containing YAML *templates* (with placeholders instead of hardcoded values) plus a `values.yaml` file supplying the defaults that fill those placeholders in.

Two very different ways this repo actually uses that idea, worth telling apart:

- **Charts you write yourself**, like `charts/otel-collector` — a template plus values files you control, versioned in this git repo.
- **Charts you install from someone else**, like SigNoz — `helm repo add signoz https://charts.signoz.io` then `helm install signoz signoz/signoz` pulls a chart someone else built and published, the same way `npm install` pulls someone else's package. You never see SigNoz's templates; you just supply values (or accept its defaults) and get a working deployment.

Both cases go through the exact same rendering engine described below — the only difference is who wrote the templates.

## What problem does Helm actually solve?

`kubectl apply -f some-file.yaml` needs a fully concrete YAML file — every value spelled out, nothing variable. That's completely fine if you only ever have **one** environment. The moment you need the *same shape* of Deployment three times (dev/stg/prod) with a handful of different values (replica count, which config file, an env var), plain `kubectl` gives you two bad options:

1. Hand-maintain three nearly-identical YAML files. Change something structural (add a probe, a new port) and you now have to remember to make the exact same edit in three places — easy to let them drift out of sync, and nothing warns you when they do.
2. Script your way around it with `sed`/sample `envsubst` hacks on a template YAML file — works, but it's ad hoc string substitution with no real language behind it (no conditionals, no functions, no validation).

Helm formalizes option 2 into a real (if quirky) templating language, plus a convention for where the "variable" parts live (`values.yaml` + per-env overrides). That's the entire value proposition for how this repo actually uses it: **one template, several small values files, instead of N copies of a full manifest.**

Concretely, in this repo: without Helm, `charts/otel-collector/templates/deployment.yaml` would need to become `deployment-dev.yaml`, `deployment-stg.yaml`, `deployment-prod.yaml` — three full files, differing only in `replicas:`, one `args:` block, and a couple of env var values. With Helm, it's one file plus three tiny values files (`values-dev.yaml` is 7 lines).

## The lifecycle — how all these files are actually used at runtime

```
STEP 1  values.yaml + values-dev.yaml
              |
              v
        MERGE  ->  one merged values map
              |
              v
STEP 2  _helpers.tpl
              |
              v
        REGISTER  ->  named helpers defined here, nothing runs yet
              |
              v
STEP 3  deployment.yaml + service.yaml
              |
              v
        RENDER  ->  each file rendered top-to-bottom using the merged
              |      values map, calling registered helpers by name
              v
STEP 4  CONCATENATE  ->  one combined YAML output
              |          (this is exactly what `helm template` prints)
              v
STEP 5  APPLY  ->  install/upgrade only, NOT `helm template`
```

**Step 1 — Merge** — Helm loads the chart's own `values.yaml` automatically, then every `-f <file>` you pass merges on top, in order, later ones winning on conflicts:

```bash
helm template otel-collector-dev charts/otel-collector \
  -f charts/otel-collector/values.yaml \
  -f charts/otel-collector/values-dev.yaml
```

Result: one merged map — `configFile` becomes `/etc/otelcol-contrib/config.dev.yaml` (from `values-dev.yaml`), `image.repository` falls through untouched from `values.yaml` since `values-dev.yaml` never mentions it. See the actual merged map with:

```bash
helm install otel-collector-dev-test charts/otel-collector \
  -f charts/otel-collector/values.yaml -f charts/otel-collector/values-dev.yaml \
  --dry-run --debug -n otel-collector-dev
```
(`--dry-run` = nothing gets created; prints `COMPUTED VALUES`, the full merged result)

**Step 2 — Register** — Helm reads `_helpers.tpl` and finds `{{- define "otel-collector.fullname" -}} ... {{- end -}}` blocks. These get *registered by name*, not run. The underscore prefix is the convention for "this file has no output of its own."

**Step 3 — Render** — `deployment.yaml` and `service.yaml` each get executed top to bottom, using the one merged values map from Step 1. Whenever one hits `{{ include "otel-collector.fullname" . }}`, *that's* the moment the matching helper from Step 2 actually runs, and its result gets spliced in right there.

**Step 4 — Concatenate** — the two separately-rendered YAML docs get joined into one output, each preceded by a `# Source: ...` comment. This is exactly what `helm template` prints to your terminal.

**Step 5 — Apply** — only for `helm install`/`helm upgrade`, never for `helm template`. The rendered YAML gets sent to the Kubernetes API. Plain Helm also records this as a "release" (enables `helm rollback`) — but **Argo CD does its own version of Steps 1-4 internally and applies the result directly**, skipping the "record a release" part. That's why `helm list -n otel-collector-dev` comes back empty even though the Deployment is running.

Interesting difference in *how* Step 5 actually happens, verified by checking both projects' own source/docs: **Argo CD literally spawns the real `kubectl` binary as a subprocess** to apply — its own docs describe running `kubectl apply` (or `kubectl apply --server-side --force-conflicts` for server-side apply), reusing kubectl's exact patch-merge behavior rather than reimplementing it. **Helm, by contrast, never shells out to `kubectl` at all** — it talks to the Kubernetes API directly via `client-go` (confirmed in Helm's own `go.mod`; a search of its source for `kubectl` subprocess calls turns up nothing), even though it imports some of kubectl's *Go code* in-process for shared logic like the apply algorithm. So for one sync of `otel-collector-dev`: Argo CD runs Steps 1-4 using Helm's Go libraries internally, then hands the result to a real `kubectl apply` subprocess for Step 5.

## Walking through `deployment.yaml` block by block

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "otel-collector.fullname" . }}
```

`{{ ... }}` marks anything Helm needs to evaluate before this becomes real YAML — everything else on the page is passed through untouched. `include "otel-collector.fullname" .` calls a named template defined in `templates/_helpers.tpl` (a small function, essentially), passing `.` — the "current context" — so that function can see `.Values`, `.Chart`, `.Release` too. This is why every resource in this chart gets consistently named (`otel-collector-dev`, `otel-collector-prod`, etc.) without typing that logic out per-file.

```yaml
  labels:
    {{- include "otel-collector.labels" . | nindent 4 }}
```

Two things worth naming explicitly, since they're the most common beginner trip-up:

- `{{-` (the dash) trims the newline/whitespace *before* this tag — without it, `include` blocks tend to leave a stray blank line that can quietly break YAML indentation.
- `| nindent 4` — the included template returns several lines of raw text (`app.kubernetes.io/name: otel-collector\napp.kubernetes.io/instance: ...`); `nindent 4` re-indents every line of that block by 4 spaces so it lands correctly nested under `labels:`. Forgetting `nindent` (or getting the number wrong) is the single most common way to produce invalid YAML from an otherwise-correct template — worth knowing that's what it's for when you see it everywhere in these files.

```yaml
  replicas: {{ .Values.replicaCount }}
```

A direct value lookup — no function, no include, just "put whatever `replicaCount` resolves to here." This is the plainest case of what Helm is for: `values.yaml` sets it to `1` by default, `values-prod.yaml` overrides it to `2`. Same template, different number, depending which values files got passed at render time.

```yaml
          {{- if .Values.configFile }}
          args:
            - --config={{ .Values.configFile }}
          {{- end }}
```

A conditional — not just a value substitution, an entire YAML block that only exists at all if `configFile` is set. This is the actual mechanism behind dev sending telemetry only to SigNoz: `values-dev.yaml` sets `configFile: /etc/otelcol-contrib/config.dev.yaml`, so the rendered dev Deployment gets an `args:` block; `values-stg.yaml`/`values-prod.yaml` never set it, so for them this entire block **doesn't exist** in the rendered output — not "exists but empty," genuinely absent. Try it yourself:

```bash
helm template otel-collector-dev charts/otel-collector -f charts/otel-collector/values.yaml -f charts/otel-collector/values-dev.yaml | grep -A1 args:
# args:
#   - --config=/etc/otelcol-contrib/config.dev.yaml

helm template otel-collector-prod charts/otel-collector -f charts/otel-collector/values.yaml -f charts/otel-collector/values-prod.yaml | grep -A1 args:
# (nothing)
```

```yaml
            - name: NEW_RELIC_OTLP_ENDPOINT
              value: {{ .Values.otelConfig.newRelicOtlpEndpoint | quote }}
```

`|` is a **pipe** — same idea as a shell pipe, feeding the value on the left into the function on the right. `quote` wraps the result in `"..."`. Without it, a value like `staging` would render as an unquoted YAML scalar; usually harmless, but some values (`true`, `false`, `yes`, `no`, plain numbers) mean something different to a YAML parser unquoted vs. quoted — `quote` sidesteps that whole class of bug by always producing a string.

```yaml
            - name: NEW_RELIC_LICENSE_KEY
              {{- if .Values.newRelicLicenseKey.existingSecret }}
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.newRelicLicenseKey.existingSecret }}
                  key: {{ .Values.newRelicLicenseKey.existingSecretKey }}
              {{- else }}
              value: {{ .Values.newRelicLicenseKey.value | quote }}
              {{- end }}
```

The clearest example in this file of templating doing something `kubectl` genuinely can't: **this renders two structurally different shapes of YAML** for the exact same env var, chosen by a single value. If `existingSecret` is set (stg/prod, pointing at the `nr-license` Secret), you get a `valueFrom.secretKeyRef` block. If it's empty (dev, which no longer references New Relic at all), you get a plain `value: ""` instead — a completely different YAML shape, from one template. There's no `kubectl` equivalent to this — you'd need two separate hand-written manifests.

## What `kubectl` alone genuinely can, and can't, do here

Worth being precise about this, since Helm can feel like it's solving problems it isn't:

| Task | Plain `kubectl` | Helm |
|---|---|---|
| Apply one, unchanging Deployment | ✅ Totally fine, no templating needed | Overkill |
| Same shape, 3 environments, few different values | ⚠️ Possible (copy-paste 3 files), error-prone | ✅ What it's actually for |
| A resource that structurally differs per environment (the `NEW_RELIC_LICENSE_KEY` example above) | ⚠️ Possible (hand-write both variants) | ✅ One template, real conditionals |
| Track "what changed between this deploy and the last one," roll back a bad release | ❌ Not built in | ✅ `helm history`, `helm rollback` (though this repo doesn't use these directly — see below) |
| Package a chart for others to reuse (e.g. the SigNoz chart you installed from `https://charts.signoz.io`) | ❌ Not a `kubectl` concept | ✅ Charts are a real distributable package format |

## Where Helm's job ends and Argo CD's begins

Easy thing to blur together, worth being explicit about: **Helm's job is turning a template + values into plain YAML. That's it.** It doesn't know or care how that YAML gets applied to a cluster, or whether it needs re-applying later.

In this repo, you never actually run `helm install`/`helm upgrade` by hand for `pulse-api`/`otel-collector`/`greetings-api` (only used that manually a couple of times while debugging). Argo CD does that step for you: it watches this git repo, and on every sync it does the Helm-render step internally (equivalent to `helm template` with your `values.yaml` + `values-{env}.yaml`), then applies the result and keeps watching for drift. Helm is the templating engine; Argo CD is what decides *when* to run it and *keeps* the cluster matching what it produces.

## `values.yaml` + `values-dev.yaml` — how the layering actually works

Every `helm template`/`helm upgrade` command in this repo passes **two** `-f` flags:

```bash
helm template otel-collector-dev charts/otel-collector -f charts/otel-collector/values.yaml -f charts/otel-collector/values-dev.yaml
```

`values.yaml` is the full set of defaults — every key the templates could possibly need, with sensible fallback values. `values-dev.yaml` is deliberately tiny (7 lines) — it only lists the keys that need to be *different* for dev. Helm merges them, with the later file (`values-dev.yaml`) winning on anything it sets, and everything it doesn't mention falling through to `values.yaml`'s default. That's why `values-dev.yaml` doesn't need to repeat `image.repository` or `resources.limits` — those are identical everywhere, so they only exist once, in the shared defaults file.

## Try it yourself

```bash
helm template otel-collector-dev charts/otel-collector -f charts/otel-collector/values.yaml -f charts/otel-collector/values-dev.yaml
```

This is the exact same rendering step Argo CD does internally before applying anything — running it locally is the fastest way to see what a template+values combination actually produces, before it ever touches the cluster. Every chart in this repo was checked this way (plus `helm lint`) before being committed.
