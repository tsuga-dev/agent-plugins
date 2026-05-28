# OTel Collector — Exporter Configuration Rules

## Protocol Decision

| Scenario | Use |
|----------|-----|
| Collector → backend (default) | OTLP/gRPC (port 4317) — better throughput, binary encoding |
| Proxies block HTTP/2 | OTLP/HTTP (port 4318) |
| Prometheus scrape endpoint needed | `prometheus` exporter |
| Debug / local development | `debug` exporter |

**Why gRPC over HTTP:** gRPC uses HTTP/2 multiplexing — lower latency, higher throughput, binary protobuf. OTLP/HTTP adds base64 encoding overhead and loses multiplexing.

## OTLP Exporter — Full Production Configuration

```yaml
exporters:
  otlp:
    endpoint: "${OTEL_EXPORTER_ENDPOINT}"  # e.g., backend.example.com:4317
    compression: gzip                        # REQUIRED: reduces bandwidth 60-80%
    headers:
      authorization: "Bearer ${BACKEND_API_KEY}"
    tls:
      insecure: false  # Always use TLS in production
      # ca_file: /etc/otelcol/ca.crt  # If using custom CA
    sending_queue:
      enabled: true
      storage: file_storage    # Persistent disk queue — survives Collector restarts
      queue_size: 5000         # Number of batches to queue (tune based on disk space)
      num_consumers: 10        # Parallel export workers
    retry_on_failure:
      enabled: true
      initial_interval: 5s
      max_interval: 30s
      max_elapsed_time: 300s   # Stop retrying after 5 minutes
    timeout: 30s
```

## Persistent Queue with file_storage

`sending_queue` with `file_storage` is the preferred buffering mechanism (vs `batch` processor):

```yaml
extensions:
  file_storage:
    directory: /var/lib/otelcol/file_storage  # Must be a mounted persistent volume
    timeout: 10s
    compaction:
      on_start: true
      on_rebound: true
      rebound_needed_threshold_mib: 100

service:
  extensions: [file_storage]
```

In Kubernetes, mount a PVC or emptyDir (emptyDir survives container restarts within a pod but is lost when the pod is deleted or rescheduled):
```yaml
volumeMounts:
  - name: otelcol-storage
    mountPath: /var/lib/otelcol/file_storage
volumes:
  - name: otelcol-storage
    emptyDir: {}
```

## Compression

Always enable `compression: gzip`. Reduces egress bandwidth 60-80% with negligible CPU overhead.

**BAD:**
```yaml
exporters:
  otlp:
    endpoint: "backend:4317"
    # No compression
```

**GOOD:**
```yaml
exporters:
  otlp:
    endpoint: "backend:4317"
    compression: gzip
```

## Multiple Exporters (Fan-out)

```yaml
exporters:
  otlp/primary:
    endpoint: "${PRIMARY_BACKEND}:4317"
    compression: gzip
    sending_queue:
      storage: file_storage
  otlp/secondary:
    endpoint: "${SECONDARY_BACKEND}:4317"
    compression: gzip

service:
  pipelines:
    traces:
      exporters: [otlp/primary, otlp/secondary]  # Fan-out: sends to both
```

## OTLP/HTTP Exporter (when gRPC blocked)

```yaml
exporters:
  otlphttp:
    endpoint: "https://backend.example.com"  # Note: no port path; /v1/traces etc. appended automatically
    compression: gzip
    headers:
      authorization: "Bearer ${API_KEY}"
    sending_queue:
      storage: file_storage
    retry_on_failure:
      enabled: true
      max_elapsed_time: 300s
```
