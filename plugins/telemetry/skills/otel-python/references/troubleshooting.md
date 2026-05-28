# Endpoint, Protocol, and Troubleshooting — Python

## OTLP Protocol Reference

| Protocol | Port | Path auto-appended by SDK? | Package |
|---|---|---|---|
| OTLP/HTTP (recommended default) | 4318 | Yes (`/v1/traces`, `/v1/metrics`, `/v1/logs`) | `opentelemetry-exporter-otlp-proto-http` |
| OTLP/gRPC | 4317 | No | `opentelemetry-exporter-otlp-proto-grpc` |

The recommended default for Python SDK setup is **HTTP/protobuf on port 4318**. HTTP exporters auto-append the signal path — do not include `/v1/traces` in `OTEL_EXPORTER_OTLP_ENDPOINT` when using HTTP.

## Tsuga Endpoint Configuration

**HTTP/protobuf (recommended default):**

```python
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter

trace_exporter = OTLPSpanExporter(
    endpoint="https://ingest.<region>.tsuga.cloud:443/v1/traces",
    headers={"tsuga-ingestion-key": os.environ["TSUGA_INGESTION_KEY"]},
)
```

**gRPC (opt-in):**

```python
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

trace_exporter = OTLPSpanExporter(
    endpoint="https://ingest.<region>.tsuga.cloud:443",
    headers={"tsuga-ingestion-key": os.environ["TSUGA_INGESTION_KEY"]},
)
```

**Via environment variables:**

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://ingest.<region>.tsuga.cloud:443
OTEL_EXPORTER_OTLP_HEADERS=tsuga-ingestion-key=<your-key>
OTEL_EXPORTER_OTLP_PROTOCOL=grpc  # or http/protobuf
OTEL_SERVICE_NAME=my-service
```

> To determine the correct service name, see `references/resource-attributes.md` → **Resolve resource attribute values**.

> **HTTP path note:** When `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`, the Python SDK appends `/v1/traces` to `OTEL_EXPORTER_OTLP_ENDPOINT` automatically. Set only the base URL in the env var.

## Common Issues

### No spans arriving

1. **Wrong endpoint format for gRPC:** gRPC endpoint must be `http://host:4317` (with `http://` in Python, unlike Go). The Python gRPC exporter expects a URL with scheme.
2. **`set_tracer_provider` not called:** Without this, `trace.get_tracer()` returns a noop tracer.
3. **Exporter not configured:** `TracerProvider()` with no `BatchSpanProcessor` sends no data.
4. **Module import order:** OTel setup must run before importing instrumented libraries.

### gRPC TLS for Tsuga (port 443)

```python
import grpc
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

# For TLS (Tsuga uses TLS on port 443)
credentials = grpc.ssl_channel_credentials()
trace_exporter = OTLPSpanExporter(
    endpoint="https://ingest.<region>.tsuga.cloud:443",
    headers={"tsuga-ingestion-key": os.environ["TSUGA_INGESTION_KEY"]},
    credentials=credentials,
)
```

When using `OTEL_EXPORTER_OTLP_ENDPOINT` with `https://`, the gRPC exporter automatically uses TLS.

### `AttributeError` on OTel API calls

Caused by version mismatch between `opentelemetry-api` and `opentelemetry-sdk`. Both must be the same version:

```bash
pip install "opentelemetry-api==1.40.0" "opentelemetry-sdk==1.40.0"
```

### Flask/Django spans missing

- `FlaskInstrumentor().instrument()` / `DjangoInstrumentor().instrument()` not called before app creation
- `OTEL_PYTHON_EXCLUDED_URLS` incorrectly set — check regex syntax

### Metrics arriving but stale

`PeriodicExportingMetricReader` exports on a schedule (default 60 seconds). For faster testing:

```python
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader

reader = PeriodicExportingMetricReader(
    exporter=OTLPMetricExporter(),
    export_interval_millis=5000,  # 5 seconds for testing
)
```

### `opentelemetry-instrument` command not found

```bash
pip install opentelemetry-distro
# Ensure the bin directory is on PATH
which opentelemetry-instrument
```

### Debug output

```bash
OTEL_PYTHON_LOG_LEVEL=debug opentelemetry-instrument python app.py
# Shows exporter configuration, span creation, and export attempts
# Note: the Python SDK does not honor the spec-level OTEL_LOG_LEVEL; use OTEL_PYTHON_LOG_LEVEL instead.
```

## Shutdown / Flush

The Python SDK's `BatchSpanProcessor` buffers spans and exports on a schedule. On process exit, `tracer_provider.shutdown()` flushes remaining spans.

**Recommended shutdown:**

```python
import atexit
import signal

tracer_provider = TracerProvider(resource=resource)
# ... configure ...

def shutdown_otel():
    tracer_provider.shutdown()
    meter_provider.shutdown()

# Register for normal exit
atexit.register(shutdown_otel)

# Register for SIGTERM (containers, Kubernetes)
signal.signal(signal.SIGTERM, lambda s, f: (shutdown_otel(), exit(0)))
```

**FastAPI lifespan:**

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: OTel is already configured at module import
    yield
    # Shutdown: flush remaining spans
    tracer_provider.shutdown()
    meter_provider.shutdown()

app = FastAPI(lifespan=lifespan)
```

**uWSGI / Gunicorn:**

```python
# gunicorn.conf.py
def worker_exit(server, worker):
    from opentelemetry import trace, metrics
    tp = trace.get_tracer_provider()
    mp = metrics.get_meter_provider()
    if hasattr(tp, "shutdown"):
        tp.shutdown()
    if hasattr(mp, "shutdown"):
        mp.shutdown()
```

**Common shutdown mistakes:**

- `atexit` not registered — no flush on SIGTERM in containers
- Calling `sys.exit()` directly instead of letting the process terminate normally — `atexit` handlers run on normal exit but not on `os._exit()`
- Not awaiting async shutdown — in async frameworks, shutdown must be awaited or scheduled in the event loop

## Resilience: Collector Unavailable

When the OTLP collector or backend is unreachable, the Python SDK does **not** crash the service. The `BatchSpanProcessor` retries exports with backoff and silently drops spans if the queue fills. The service continues operating normally.

**Default behavior:** The gRPC and HTTP exporters retry connection failures with exponential backoff. Spans accumulate in the buffer; once the buffer is full, older spans are dropped. No exception is raised to application code.

**Explicit no-op fallback** (e.g., in dev/test when no collector is available):

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter

def setup_tracing(collector_endpoint: str | None = None):
    provider = TracerProvider(resource=resource)
    if collector_endpoint:
        from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
        provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=collector_endpoint)))
    else:
        # No collector configured — spans are created but not exported (no crash)
        pass  # TracerProvider with no processor = functional no-op
    trace.set_tracer_provider(provider)
```

**Key point:** A `TracerProvider` with no `SpanProcessor` is fully functional — spans are created, context propagates, but nothing is exported. This is the recommended "graceful degradation" pattern: always initialize OTel, but only add an exporter if the endpoint is configured.

**Verify the service still works:**
```bash
# Start the service without a collector — it should start without errors
OTEL_SDK_DISABLED=true python app.py  # completely disables all OTel (SDK v1.20+)
# or just don't set OTEL_EXPORTER_OTLP_ENDPOINT — SDK will use default and retry silently
```
