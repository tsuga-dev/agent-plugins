---
name: otel-collector
description: "Use whenever Collector YAML needs to be written or debugged, or when someone asks about Collector pipelines, processors, or deployment."
---

# OTel Collector Reference

> **Last verified:** 2026-03-22 | Collector version: `otelcol-contrib` v0.120.0

## When to Use This Skill

- Writing or reviewing Collector YAML configuration
- Choosing between DaemonSet, Deployment (Gateway), or Sidecar topology
- Configuring processor ordering (memory_limiter MUST be first)
- Setting up tail sampling or head sampling
- Configuring exporters with persistent queues
- Deploying the Collector on Kubernetes

> **For Kubernetes deployments: load `references/helm-chart.md` first.** The Tsuga Helm chart (v0.6.2) is the preferred deployment path — it handles RBAC, image management, and Tsuga credentials automatically. Use `references/deployment.md` only for non-Kubernetes environments or when Helm is unavailable.

## Rule Files (Load on Demand)

| File | When to Load |
|------|-------------|
| [`references/helm-chart.md`](references/helm-chart.md) | **Kubernetes deployments** — Helm chart install, secret management, extending defaults, audit/converge |
| [`references/pipelines.md`](references/pipelines.md) | Writing or reviewing pipeline topology |
| [`references/processors.md`](references/processors.md) | Configuring any processor; ordering questions |
| [`references/exporters.md`](references/exporters.md) | Configuring OTLP or other exporters |
| [`references/receivers.md`](references/receivers.md) | Configuring OTLP, Prometheus, filelog, or other receivers |
| [`references/sampling.md`](references/sampling.md) | Head sampling, tail sampling, or loadbalancing decisions |
| [`references/deployment.md`](references/deployment.md) | Non-Kubernetes: raw DaemonSet/Gateway/Sidecar YAML patterns |

## Quick Start: Minimal Working Configuration

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
      http:
        endpoint: 0.0.0.0:4318

processors:
  memory_limiter:
    check_interval: 1s
    limit_percentage: 80
    spike_limit_percentage: 25
  resourcedetection:
    detectors: [env, system, docker]
    override: false
  batch:  # NOTE: Only use batch if NOT using sending_queue at exporter level
    timeout: 200ms
    send_batch_size: 1000

exporters:
  otlp:
    endpoint: "your-backend:4317"
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

> See `references/processors.md` for the critical note on `batch` processor vs `sending_queue`.

## Limitations

- Collector configuration is highly version-dependent; verify component availability in your `otelcol-contrib` version
- Tail sampling requires all spans of a trace to reach the same Collector instance — architecture matters (see `references/sampling.md`)
- `k8s_attributes` processor requires RBAC permissions; see `references/deployment.md`
- File storage extension requires a writable volume mount in containers
