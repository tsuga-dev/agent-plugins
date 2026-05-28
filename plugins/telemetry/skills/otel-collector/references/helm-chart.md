---
last_verified: 2026-03-23
chart_version: "0.6.2"
---

# OTel Collector — Tsuga Helm Chart Reference

> **Preferred deployment path for Kubernetes.** The Tsuga Helm chart deploys the full OTel collector infrastructure via the OpenTelemetry Operator (`OpenTelemetryCollector` CRD). Use `deployment.md` only for non-Kubernetes environments or when Helm is unavailable.

## Decision Gate

| Situation | Action |
|-----------|--------|
| Deploying on Kubernetes, no existing collector | **Use this file** — Helm chart is the preferred path |
| Already have a collector running on Kubernetes | See [Audit → Converge](#audit--converge-existing-collector) below |
| Non-Kubernetes (bare metal, docker-compose, VM) | Use `deployment.md` — raw YAML patterns |
| Helm unavailable or cluster restrictions prevent CRDs | Use `deployment.md` — raw YAML patterns |

---

## Prerequisites

Install cert-manager and the OpenTelemetry Operator before the chart:

```bash
# 1. cert-manager (required by the OTel Operator's webhooks)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
kubectl wait --for=condition=Ready pods --all -n cert-manager --timeout=300s

# 2. OpenTelemetry Operator
#    Option A: let the chart install it (simplest)
#    --set opentelemetry-operator.enabled=true   (see Install section)
#
#    Option B: install separately if you manage the operator yourself
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml
kubectl wait --for=condition=Ready pods --all -n opentelemetry-operator-system --timeout=300s
```

---

## Install

```bash
# Add chart repo
helm repo add tsuga-charts https://tsuga-dev.github.io/helm-charts/
helm repo update

# Install (credentials via --set, NEVER in values.yaml or committed files)
helm install otel-stack tsuga-charts/opentelemetry-kube-stack \
  --namespace monitoring --create-namespace \
  --set clusterName="<your-cluster-name>" \
  --set tsuga.otlpEndpoint="<your-tsuga-endpoint>" \
  --set tsuga.apiKey="<your-api-key>" \
  --set secret.create=true

# Optional: bundle the OTel Operator install
# Add: --set opentelemetry-operator.enabled=true
```

---

## Required Values

All three values MUST be set. Omitting any silently breaks data collection.

| Value | Required | Default | Effect if Omitted |
|-------|----------|---------|-------------------|
| `clusterName` | **YES** | `""` | `k8s.cluster.name` dropped from ALL telemetry — cluster attribution breaks |
| `tsuga.otlpEndpoint` | **YES** | `""` | No data reaches Tsuga |
| `tsuga.apiKey` | **YES** | `""` | All exports rejected (401) |
| `secret.create` | YES unless using external secrets | `false` | Credentials not mounted; collector fails to start |

**BAD** — omits `clusterName`:
```bash
helm install otel-stack tsuga-charts/opentelemetry-kube-stack \
  --set tsuga.otlpEndpoint="https://..." \
  --set tsuga.apiKey="key-..."
# All telemetry arrives without k8s.cluster.name — unfilterable in Tsuga
```

**GOOD** — all required values set:
```bash
helm install otel-stack tsuga-charts/opentelemetry-kube-stack \
  --set clusterName="prod-us-east-1" \
  --set tsuga.otlpEndpoint="https://ingest.tsuga.io/v1/otel" \
  --set tsuga.apiKey="key-abc123" \
  --set secret.create=true
```

---

## What the Chart Deploys

### Agent (DaemonSet) — one pod per node

- `hostNetwork: true` — binds to node IP; apps send to `$(K8S_NODE_IP):4317`
- Receivers: `otlp` (4317/4318), `filelog` (/var/log/pods), `hostmetrics`, `kubeletstats`, `prometheus`, `jaeger`, `zipkin`
- Processors: `memory_limiter` → `k8s_attributes` → `batch` → `cumulativetodelta` → `resource`
- Pipelines: logs (`otlp`, `filelog`), metrics (all receivers), traces (`otlp`, `jaeger`, `zipkin`)
- Exporter: `otlphttp/tsuga` authenticated via Secret

Notable agent toggles:

| Value | Default | Effect |
|-------|---------|--------|
| `agent.collectLogs` | `true` | filelog receiver on/off |
| `agent.collectNetwork` | `false` | network interface metrics |
| `agent.collectProcesses` | `false` | per-process metrics (high cardinality) |

### Cluster Receiver (Deployment) — single pod

- Receivers: `k8s_cluster` (cluster metrics + entity events; `k8sobjects` optional)
- Processors: `k8s_attributes` → `resource` (adds `k8s.cluster.name`)
- Exporter: `otlphttp/tsuga`

### Optional Components

| Component | Enable With | Purpose |
|-----------|-------------|---------|
| StatefulSet + TargetAllocator | `targetAllocator.enabled=true` | Prometheus scraping at scale |
| Auto-instrumentation | `autoInstrumentation.enabled=true` | Zero-code SDK injection via `Instrumentation` CR |
| OTel Operator | `opentelemetry-operator.enabled=true` | Bundle operator install with chart |

---

## Secret Management

### Option 1: `--set` flags (simplest, non-production)

```bash
helm install otel-stack ... \
  --set tsuga.apiKey="key-abc123" \
  --set secret.create=true
```

### Option 2: Pre-created Kubernetes Secret

Create the Secret before installing:
```bash
kubectl create secret generic tsuga-credentials \
  --namespace monitoring \
  --from-literal=TSUGA_API_KEY="key-abc123" \
  --from-literal=TSUGA_OTLP_ENDPOINT="https://ingest.tsuga.io/v1/otel"

helm install otel-stack tsuga-charts/opentelemetry-kube-stack \
  --set clusterName="prod-us-east-1" \
  --set secret.create=false \
  --set secret.name="tsuga-credentials"
```

### Option 3: External Secrets Operator

```yaml
# ExternalSecret resource — sync from your secrets store
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: tsuga-credentials
  namespace: monitoring
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: my-secret-store
    kind: ClusterSecretStore
  target:
    name: tsuga-credentials
  data:
    - secretKey: TSUGA_API_KEY
      remoteRef:
        key: tsuga/api-key
    - secretKey: TSUGA_OTLP_ENDPOINT
      remoteRef:
        key: tsuga/otlp-endpoint
```

Then install with `--set secret.create=false --set secret.name=tsuga-credentials`.

---

## Extending Defaults (Merge-Based)

Use merge-based extension to add config without replacing the full pipeline. Prefer this over `customConfig`.

### Add a receiver

```yaml
# values.yaml
agent:
  config:
    extraReceivers:
      redis:
        endpoint: "redis-service:6379"
        collection_interval: 10s
```

**BAD** — replacing all receivers:
```yaml
agent:
  customConfig:
    receivers:
      otlp: ...          # must re-specify ALL receivers
      redis: ...
```

**GOOD** — merge only the new receiver:
```yaml
agent:
  config:
    extraReceivers:
      redis:
        endpoint: "redis-service:6379"
```

### Add a processor

```yaml
agent:
  config:
    extraProcessors:
      attributes/add-env:
        actions:
          - key: deployment.environment.name
            value: "production"
            action: insert
```

### Add an exporter (fan-out)

```yaml
agent:
  config:
    extraExporters:
      otlp/secondary:
        endpoint: "secondary-backend:4317"
    service:
      pipelines:
        traces:
          extraExporters: [otlp/secondary]
```

---

## Tail Sampling via customConfig

The default agent does not include `tail_sampling`. To add it, you must either:

**Option A: Agent with local tail sampling (single-node only, not recommended at scale)**

```yaml
agent:
  customConfig:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    processors:
      memory_limiter:
        check_interval: 1s
        limit_percentage: 80
        spike_limit_percentage: 25
      tail_sampling:
        decision_wait: 10s
        policies:
          - name: errors-or-slow
            type: composite
            composite:
              max_total_spans_per_second: 1000
              policy_order: [errors, slow-traces]
              composite_sub_policy:
                - name: errors
                  type: status_code
                  status_code: {status_codes: [ERROR]}
                - name: slow-traces
                  type: latency
                  latency: {threshold_ms: 500}
              rate_allocation:
                - policy: errors
                  percent: 50
                - policy: slow-traces
                  percent: 50
      batch:
        timeout: 200ms
    exporters:
      otlphttp/tsuga:
        endpoint: "${TSUGA_OTLP_ENDPOINT}"
        headers:
          Authorization: "Bearer ${TSUGA_API_KEY}"
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, tail_sampling, batch]
          exporters: [otlphttp/tsuga]
```

**Option B: Gateway Deployment for tail sampling at scale (recommended)**

Deploy a separate gateway collector (see `deployment.md` → Gateway Deployment Pattern) and configure the agent to forward via `loadbalancingexporter`. See `references/sampling.md` for the full loadbalancing + tail sampling architecture.

---

## Auto-Instrumentation

Enable zero-code SDK injection for applications that have not been manually instrumented:

```bash
helm upgrade otel-stack tsuga-charts/opentelemetry-kube-stack \
  --reuse-values \
  --set autoInstrumentation.enabled=true
```

Then create an `Instrumentation` CR targeting your namespace:

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: tsuga-instrumentation
  namespace: my-app-namespace
spec:
  exporter:
    endpoint: http://$(K8S_NODE_IP):4317   # Routes to DaemonSet agent
  propagators:
    - tracecontext
    - baggage
    - b3
  sampler:
    type: parentbased_traceidratio
    argument: "1.0"
  java:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:latest
  nodejs:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:latest
  python:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-python:latest
  dotnet:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-dotnet:latest
```

Annotate pods to inject the SDK:
```yaml
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-java: "tsuga-instrumentation"
    # Or: inject-nodejs, inject-python, inject-dotnet
```

---

## Verification

After install, verify the collector is running and sending data:

```bash
# 1. Check pods
kubectl get pods -n monitoring
# Expected: otel-stack-agent-<hash> (one per node), otel-stack-cluster-receiver-<hash>

# 2. Check agent logs for export errors
kubectl logs -n monitoring -l app.kubernetes.io/component=opentelemetry-collector --tail=50

# 3. Verify credentials are mounted
kubectl exec -n monitoring \
  $(kubectl get pod -n monitoring -l app.kubernetes.io/component=opentelemetry-collector -o jsonpath='{.items[0].metadata.name}') \
  -- env | grep TSUGA_

# 4. Check for pipeline errors in collector metrics
kubectl port-forward -n monitoring svc/otel-stack-agent 8888:8888 &
curl -s http://localhost:8888/metrics | grep otelcol_exporter_send_failed
# Should be 0 or not increasing
```

---

## Audit → Converge Existing Collector

Use this process when a customer already has a collector running and wants to migrate to or align with the Helm chart defaults.

### Step 1: Inventory the existing config

```bash
# Get the current collector config
kubectl get configmap -n monitoring otelcol-config -o yaml
# Or for OTel Operator CRD:
kubectl get opentelemetrycollector -A -o yaml
```

### Step 2: Compare against chart defaults

Map each custom component to its Helm chart equivalent:

| Existing Config | Chart Equivalent | Notes |
|-----------------|-----------------|-------|
| Custom receiver | `agent.config.extraReceivers` | Merge-safe |
| Custom processor | `agent.config.extraProcessors` | Merge-safe; mind ordering |
| Custom exporter | `agent.config.extraExporters` + `service.pipelines.<signal>.extraExporters` | Merge-safe |
| Full pipeline override | `agent.customConfig` | Only if incompatible with merge approach |
| Existing credentials Secret | `secret.create=false`, `secret.name=<existing>` | Reuse; no change to Secret |

### Step 3: Choose merge-based or customConfig

**Use merge-based (`extraReceivers`, `extraProcessors`, `extraExporters`) when:**
- Adding new receivers, processors, or exporters not in the chart defaults
- The existing pipeline structure is compatible with the chart defaults

**Use `customConfig` only when:**
- The existing pipeline order is incompatible with chart defaults
- The existing setup has fundamentally different receiver/pipeline topology
- Tail sampling is required (see tail sampling section above)

### Step 4: Install with migration values

```bash
# Migrate existing credentials (if already in a Secret)
helm install otel-stack tsuga-charts/opentelemetry-kube-stack \
  --set clusterName="<cluster-name>" \
  --set secret.create=false \
  --set secret.name="<existing-secret-name>" \
  -f migration-values.yaml   # file with extraReceivers/extraProcessors
```

### Step 5: Validate before removing old collector

Run both collectors in parallel briefly:
1. Install chart with a distinct release name
2. Verify data appears in Tsuga from the chart-deployed collector
3. Drain/remove the old collector

---

## Chart Source

Repository: `https://github.com/tsuga-dev/helm-charts/tree/main/charts/opentelemetry-kube-stack`
Current version: v0.6.2
