# OTel Collector — Receiver Configuration Rules

## Receiver Decision Table

| Data Source | Receiver to Use |
|------------|----------------|
| Instrumented apps sending OTLP | `otlp` |
| Prometheus /metrics endpoints | `prometheus` |
| Log files on disk | `filelog` |
| Host system metrics (CPU, memory, disk) | `hostmetrics` |
| Kubernetes cluster metrics | `k8s_cluster` |
| Jaeger spans (legacy migration) | `jaeger` |
| Zipkin spans (legacy migration) | `zipkin` |

## OTLP Receiver

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317     # Bind to 0.0.0.0 (not localhost) when receiving from other containers/pods
        max_recv_msg_size_mib: 16   # Default is 4 MiB; increase if large batches cause errors
      http:
        endpoint: 0.0.0.0:4318
        cors:
          allowed_origins: ["*"]   # Restrict in production
```

**CRITICAL:** Always bind to `0.0.0.0`, not `localhost` or `127.0.0.1`, when the Collector receives data from other containers or pods. `localhost` only accepts connections from the same container.

**BAD:**
```yaml
grpc:
  endpoint: localhost:4317  # Only accessible from same container
```

**GOOD:**
```yaml
grpc:
  endpoint: 0.0.0.0:4317  # Accessible from other containers/pods
```

## Prometheus Receiver

```yaml
receivers:
  prometheus:
    config:
      scrape_configs:
        - job_name: my-service
          scrape_interval: 15s
          static_configs:
            - targets: ["service-name:8080"]
          metrics_path: /metrics
```

For Kubernetes pod auto-discovery:
```yaml
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: "true"
```

## filelog Receiver

```yaml
receivers:
  filelog:
    include: [/var/log/pods/*/*/*.log]
    start_at: beginning
    include_file_path: true
    include_file_name: false
    operators:
      - type: container         # Parse container log format
        id: container-parser
      - type: json_parser       # Parse JSON structured logs
        id: json-parser
        parse_from: attributes.log
```

## hostmetrics Receiver

```yaml
receivers:
  hostmetrics:
    collection_interval: 30s
    scrapers:
      cpu:
      memory:
      disk:
      filesystem:
        exclude_mount_points:
          mount_points: [/dev, /sys, /proc]
          match_type: strict
      network:
      load:
      processes:
```

Use `hostmetrics` on DaemonSet Collectors to collect per-node system metrics. Do NOT use on Gateway Collectors (they don't have access to host resources).
