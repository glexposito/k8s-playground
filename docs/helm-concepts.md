# Helm, explained through `charts/otel-collector`

Same idea as [k8s-concepts.md](k8s-concepts.md): real files from this repo, not generic examples. This walks through `charts/otel-collector/templates/deployment.yaml` and explains what each part is for — including what `kubectl` alone could already do, so Helm doesn't feel like magic.

## What is Helm?

Helm is a **package manager for Kubernetes** — same idea as `apt` or `npm`, applied to Kubernetes YAML instead of OS packages or code libraries.

A "package" is called a **chart**: a folder of YAML *templates* (with placeholders) plus a `values.yaml` file that supplies the values filling those placeholders in.

This repo uses charts two ways:

- **Charts you write yourself**, like `charts/otel-collector` — templates and values files you own, versioned in this repo.
- **Charts you install from someone else**, like SigNoz — `helm install signoz signoz/signoz` pulls a chart someone else built, the same way `npm install` pulls someone else's package. You never see SigNoz's templates; you just supply values (or accept the defaults).

Both go through the same rendering engine described below. The only difference is who wrote the templates.

## What problem does it solve?

`kubectl apply -f file.yaml` needs a fully concrete file — every value spelled out. That's fine with one environment. Once you need the same shape of Deployment for dev/stg/prod, with a few different values (replica count, a config file, an env var), plain `kubectl` leaves two bad options:

1. **Hand-maintain three near-identical files.** Add a probe or a port and you must remember to make the same edit three times — easy to let them drift.
2. **Script around it** with `sed`/`envsubst` on a template file — works, but it's string substitution with no real language: no conditionals, no functions, no validation.

Helm turns option 2 into a real templating language, plus a convention for where the variable parts live: `values.yaml` and per-environment overrides.

Concretely: without Helm, `charts/otel-collector/templates/deployment.yaml` would need to become three full files (`deployment-dev.yaml`, `deployment-stg.yaml`, `deployment-prod.yaml`), differing only in `replicas:`, one `args:` block, and a couple of env var values. With Helm it's one template plus three tiny values files — `values-dev.yaml` is 7 lines.

## How rendering actually works

Every `helm template`/`helm upgrade` in this repo passes two `-f` flags:

```bash
helm template otel-collector-dev charts/otel-collector \
  -f charts/otel-collector/values.yaml \
  -f charts/otel-collector/values-dev.yaml
```

Four things happen, in order:

**1. Merge values.** `values.yaml` holds every default the templates could need. `values-dev.yaml` is deliberately tiny — it only lists what's *different* for dev. Helm merges the two, later files winning on conflicts: `configFile` becomes `/etc/otelcol-contrib/config.dev.yaml` (set in `values-dev.yaml`), while `image.repository` falls through untouched from `values.yaml`, since `values-dev.yaml` never mentions it.

   See the merged result yourself:
   ```bash
   helm install otel-collector-dev-test charts/otel-collector \
     -f charts/otel-collector/values.yaml -f charts/otel-collector/values-dev.yaml \
     --dry-run --debug -n otel-collector-dev
   ```
   `--dry-run` creates nothing; `--debug` prints `COMPUTED VALUES`, the full merged map.

**2. Register helpers.** Helm reads `_helpers.tpl` and registers each `{{- define "otel-collector.fullname" -}} ... {{- end -}}` block by name — like loading a function before it's called. Nothing runs yet. (The underscore prefix on the filename is the convention for "this file has no output of its own.")

**3. Render templates.** `deployment.yaml` and `service.yaml` each get executed top to bottom against the merged values map. When one hits `{{ include "otel-collector.fullname" . }}`, that's when the matching helper from step 2 actually runs and its result gets spliced in.

**4. Concatenate.** The two rendered YAML docs get joined into one output, each preceded by a `# Source: ...` comment. This is exactly what `helm template` prints to your terminal.

That's as far as Helm itself goes — it never touches the cluster. Applying the result is a separate concern, covered in [Where Helm's job ends and Argo CD's begins](#where-helms-job-ends-and-argo-cds-begins).

## Walking through `deployment.yaml` block by block

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "otel-collector.fullname" . }}
```

`{{ ... }}` marks anything Helm evaluates before this becomes real YAML — everything else passes through untouched. `include "otel-collector.fullname" .` calls a named template from `templates/_helpers.tpl`, essentially a small function. The `.` passed in is the "current context," giving that function access to `.Values`, `.Chart`, `.Release`. This is why every resource in this chart is named consistently (`otel-collector-dev`, `otel-collector-prod`, ...) without repeating that logic in every file.

```yaml
  labels:
    {{- include "otel-collector.labels" . | nindent 4 }}
```

Two details that trip up most beginners:

- `{{-` (the dash) trims the whitespace *before* the tag. Without it, `include` tends to leave a stray blank line that quietly breaks YAML indentation.
- `| nindent 4` re-indents every line the included template returns (several lines, e.g. `app.kubernetes.io/name: otel-collector\napp.kubernetes.io/instance: ...`) by 4 spaces, so it nests correctly under `labels:`. Forgetting `nindent`, or getting the number wrong, is the most common way to turn a correct template into invalid YAML — worth recognizing it wherever it shows up.

```yaml
  replicas: {{ .Values.replicaCount }}
```

A direct value lookup — no function, no include, just "put whatever `replicaCount` resolves to here." This is the plainest case of what Helm is for: `values.yaml` sets it to `1` by default, `values-prod.yaml` overrides it to `2`. Same template, different number, depending on which values files got passed at render time.

```yaml
          {{- if .Values.configFile }}
          args:
            - --config={{ .Values.configFile }}
          {{- end }}
```

A conditional: the whole `args:` block only exists if `configFile` is set. This is what makes dev send telemetry only to SigNoz — `values-dev.yaml` sets `configFile`, so dev's rendered Deployment gets an `args:` block; `values-stg.yaml`/`values-prod.yaml` never set it, so for them the block is genuinely absent from the output, not just empty. Try it:

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

`|` is a **pipe** — same idea as a shell pipe, feeding the value on the left into the function on the right. `quote` wraps the result in `"..."`. Without it, a value like `staging` would render as an unquoted YAML scalar — usually harmless, but values like `true`, `false`, `yes`, `no`, or plain numbers mean something different unquoted vs. quoted to a YAML parser. `quote` sidesteps that whole class of bug by always producing a string.

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

The clearest example of templating doing something `kubectl` genuinely can't: this renders two *structurally different* shapes of YAML for the same env var, chosen by one value.

- `existingSecret` set (stg/prod, pointing at the `nr-license` Secret) → a `valueFrom.secretKeyRef` block.
- `existingSecret` empty (dev, which doesn't use New Relic) → a plain `value: ""` instead.

Two completely different YAML shapes, from one template. There's no `kubectl` equivalent — you'd need two separate hand-written manifests.

## What `kubectl` alone can, and can't, do here

| Task | Plain `kubectl` | Helm |
|---|---|---|
| Apply one, unchanging Deployment | ✅ Totally fine, no templating needed | Overkill |
| Same shape, 3 environments, few different values | ⚠️ Possible (copy-paste 3 files), error-prone | ✅ What it's actually for |
| A resource that structurally differs per environment (the `NEW_RELIC_LICENSE_KEY` example above) | ⚠️ Possible (hand-write both variants) | ✅ One template, real conditionals |
| Track what changed between deploys, roll back a bad release | ❌ Not built in | ✅ `helm history`, `helm rollback` (this repo doesn't use these directly — see below) |
| Package a chart for others to reuse (e.g. the SigNoz chart from `https://charts.signoz.io`) | ❌ Not a `kubectl` concept | ✅ Charts are a real distributable package format |

## Where Helm's job ends and Argo CD's begins

Helm's job is turning a template + values into plain YAML. That's it — it doesn't apply anything to a cluster, and it doesn't know if the result ever needs re-applying.

In this repo, `helm install`/`helm upgrade` are never run by hand for `pulse-api`/`otel-collector`/`greetings-api` (only a couple of times, while debugging). Argo CD does that instead: it watches this git repo, and on every sync renders the chart internally — equivalent to `helm template` with `values.yaml` + `values-{env}.yaml` — then applies the result and keeps watching for drift.

Two differences worth knowing if you're debugging a sync:

- **No release history.** Plain Helm records each install as a "release," which is what `helm rollback` uses. Argo CD skips that — it renders and applies directly. That's why `helm list -n otel-collector-dev` comes back empty even though the Deployment is running.
- **How the apply itself happens.** Argo CD spawns the real `kubectl` binary as a subprocess to apply (`kubectl apply`, or `--server-side --force-conflicts` for server-side apply) — the same patch-merge behavior as running kubectl yourself. Helm itself never shells out to `kubectl`; it talks to the Kubernetes API directly via `client-go`. So for one Argo CD sync: Argo CD renders the chart using Helm's Go libraries, then hands the result to a real `kubectl apply` subprocess.

## Try it yourself

```bash
helm template otel-collector-dev charts/otel-collector -f charts/otel-collector/values.yaml -f charts/otel-collector/values-dev.yaml
```

This is the exact rendering step Argo CD does internally before applying anything — running it locally is the fastest way to see what a template + values combination actually produces, before it touches the cluster. Every chart in this repo was checked this way (plus `helm lint`) before being committed.
