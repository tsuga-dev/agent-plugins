# OTel Collector — Pipeline Wiring Rules

## Core Rules

### Rule 1: One pipeline per signal type
**BAD:**
```yaml
service:
  pipelines:
    default:
      receivers: [otlp]
      processors: [memory_limiter]
      exporters: [otlp]
```
**GOOD:**
```yaml
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, resourcedetection]
      exporters: [otlp]
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, resourcedetection]
      exporters: [otlp]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, resourcedetection]
      exporters: [otlp]
```
**Why:** Different signal types have different processing needs and cardinality characteristics. Mixing them prevents per-signal tuning.

### Rule 2: Named pipelines for multiple of the same signal type
```yaml
service:
  pipelines:
    traces/application:
      receivers: [otlp]
      processors: [memory_limiter, resourcedetection, k8s_attributes]
      exporters: [otlp/primary]
    traces/infrastructure:
      receivers: [hostmetrics]
      processors: [memory_limiter, resourcedetection]
      exporters: [otlp/primary]
```
**Why:** Named pipelines (`signal/name`) isolate processing paths for different data sources.

### Rule 3: Every declared component SHOULD appear in a pipeline
**BAD:** Declaring `k8s_attributes` in `processors:` block but not referencing it in any pipeline.

**GOOD:** Either use a component in a pipeline or remove it from the top-level block.

If a component is declared but not in any pipeline, it is silently ignored (not started). The Collector will still start, but the unused component wastes configuration clarity. Keep config clean by removing components that are not wired into a pipeline.

### Rule 4: Consistent resourcedetection + k8s_attributes across all signal pipelines
All three signal pipelines must apply the same resource detection processors. Inconsistent resource attributes across traces, metrics, and logs make correlation impossible.

**BAD:**
```yaml
traces:
  processors: [memory_limiter, resourcedetection, k8s_attributes]
metrics:
  processors: [memory_limiter]  # Missing resource enrichment
logs:
  processors: [memory_limiter, resourcedetection]  # Missing k8s_attributes
```

**GOOD:** All pipelines share the same processor chain (or a named pipeline anchors shared config).

## Minimal YAML with Service Section

```yaml
extensions:
  health_check:
  file_storage:
    directory: /var/lib/otelcol/file_storage

receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317

processors:
  memory_limiter:
    check_interval: 1s
    limit_percentage: 80
    spike_limit_percentage: 25
  resourcedetection:
    detectors: [env, system, docker]
    override: false

exporters:
  otlp:
    endpoint: "${OTEL_EXPORTER_ENDPOINT}"
    compression: gzip
    sending_queue:
      storage: file_storage
      queue_size: 5000
    retry_on_failure:
      enabled: true
      max_elapsed_time: 300s

service:
  extensions: [health_check, file_storage]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, resourcedetection]
      exporters: [otlp]
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, resourcedetection]
      exporters: [otlp]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, resourcedetection]
      exporters: [otlp]
  telemetry:
    logs:
      level: info
    metrics:
      address: 0.0.0.0:8888
```
