# OTel Collector — Processor Ordering Rules

## Critical: Required Processor Order

Processors MUST appear in this order in each pipeline. Deviation causes data loss or memory instability.

```
1. memory_limiter     ← REQUIRED FIRST — hard circuit breaker
2. resourcedetection  ← enrich with host/cloud/container metadata
3. k8s_attributes     ← enrich with pod/namespace/deployment metadata (Kubernetes only)
4. resource           ← set custom resource attributes
5. transform / filter ← enrich, redact, or drop via OTTL
```

## NO batch Processor

**Do NOT use the `batch` processor** when exporters use `sending_queue` with `file_storage`.

- `batch` processor buffers in memory — data is lost if the Collector crashes
- `sending_queue` with `file_storage` persists to disk and survives Collector restarts
- Use one or the other, not both

**BAD:**
```yaml
processors:
  memory_limiter: ...
  batch:
    timeout: 200ms
exporters:
  otlp:
    sending_queue:
      storage: file_storage
```

**GOOD (persistent queue at exporter):**
```yaml
processors:
  memory_limiter: ...
  # No batch processor
exporters:
  otlp:
    sending_queue:
      storage: file_storage
      queue_size: 5000
```

**GOOD (batch only, no persistent queue):**
```yaml
processors:
  memory_limiter: ...
  batch:
    timeout: 200ms
    send_batch_size: 1000
exporters:
  otlp:
    # No sending_queue
```

## Processor Reference

### memory_limiter (REQUIRED — always first)

```yaml
processors:
  memory_limiter:
    check_interval: 1s
    limit_percentage: 80        # Hard limit: 80% of container memory limit
    spike_limit_percentage: 25  # Spike headroom: 25% of total available memory
```

- `limit_percentage`: when memory exceeds this, Collector starts dropping new data and returning errors to senders
- `spike_limit_percentage`: absolute percentage of total available memory reserved as headroom for GC spikes (e.g., 25 means 25% of total memory, NOT 25% of `limit_percentage`)
- Set container memory limit in pod spec; `limit_percentage` is relative to that limit
- Without this processor, an overloaded Collector will OOMKill and lose all in-memory data

### resourcedetection

```yaml
processors:
  resourcedetection:
    detectors: [env, system, docker, gcp, aws, azure]
    override: false  # IMPORTANT: do not overwrite attributes set by the application
    timeout: 5s
```

- `override: false` preserves resource attributes already set by the instrumented app (e.g., `service.name`, `deployment.environment.name`)
- Detector order matters: first match wins
- Common detectors: `env` (reads `OTEL_RESOURCE_ATTRIBUTES`), `system` (hostname, OS), `docker` (container ID), `gcp`/`aws`/`azure` (cloud metadata)

### k8s_attributes (Kubernetes only — MUST have RBAC)

```yaml
processors:
  k8s_attributes:
    auth_type: serviceAccount
    passthrough: false
    extract:
      metadata:
        - k8s.pod.name
        - k8s.pod.uid
        - k8s.deployment.name
        - k8s.namespace.name
        - k8s.node.name
        - k8s.pod.start_time
    pod_association:
      - sources:
          - from: resource_attribute
            name: k8s.pod.uid
      - sources:
          - from: resource_attribute
            name: k8s.pod.ip
      - sources:
          - from: connection
```

Required RBAC (ClusterRole):
```yaml
rules:
  - apiGroups: [""]
    resources: ["pods", "namespaces", "nodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["replicasets"]
    verbs: ["get", "list", "watch"]
```

### resource (custom attribute injection)

```yaml
processors:
  resource:
    attributes:
      - key: deployment.environment.name
        value: production
        action: upsert
      - key: k8s.cluster.name
        value: "${K8S_CLUSTER_NAME}"
        action: insert  # insert: only if not already present
```

Actions: `insert` (add if missing), `update` (update if present), `upsert` (add or update), `delete`.

### transform / filter (OTTL-based)

See `otel-ottl` skill for OTTL syntax and common patterns.

```yaml
processors:
  transform:
    error_mode: ignore  # Use ignore in production (propagate stops the pipeline)
    trace_statements:
      - context: span
        statements:
          - set(span.attributes["http.request.header.authorization"], "REDACTED") where span.attributes["http.request.header.authorization"] != nil
  filter:
    error_mode: ignore
    traces:
      span:
        - 'attributes["http.route"] == "/health"'  # Drop health check spans
```
