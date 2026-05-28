# Quick Start — Python OTel SDK

> **Last verified:** 2026-03-23 | SDK: `opentelemetry-api` 1.40.0, `opentelemetry-sdk` 1.40.0

> Run `python3 --version` — Python 3.9+ required for SDK 1.40.x. If below 3.9, use opentelemetry-sdk ≤ 1.19.0 (Python 3.8) or stop if below 3.8.

Two paths: **Manual SDK init** (full control) or **Auto-instrumentation CLI** (zero-code).

---

## Path A — Manual SDK Init

### 1. Install packages

```bash
# Core (HTTP exporter — recommended default)
pip install \
  opentelemetry-api==1.40.0 \
  opentelemetry-sdk==1.40.0 \
  opentelemetry-exporter-otlp-proto-http==1.40.0 \
  opentelemetry-instrumentation-logging==0.61b0

# gRPC opt-in (replaces proto-http; requires different imports)
# pip install opentelemetry-exporter-otlp-proto-grpc==1.40.0
```

### 2. Create `otel_setup.py`

**Import this module before any app code.** `LoggingInstrumentor` must be called before logging handlers are configured — see step 3.

```python
# otel_setup.py
import atexit
from opentelemetry import trace, metrics
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter

# ⚠️ MUST be first — before any logging.getLogger() calls
from opentelemetry.instrumentation.logging import LoggingInstrumentor
LoggingInstrumentor().instrument(set_logging_format=True)

# Resource.create() (zero-arg) auto-merges OTEL_SERVICE_NAME and OTEL_RESOURCE_ATTRIBUTES
resource = Resource.create()

# Traces
tracer_provider = TracerProvider(resource=resource)
tracer_provider.add_span_processor(
    BatchSpanProcessor(OTLPSpanExporter())  # reads OTEL_EXPORTER_OTLP_ENDPOINT
)
trace.set_tracer_provider(tracer_provider)

# Metrics
meter_provider = MeterProvider(
    resource=resource,
    metric_readers=[PeriodicExportingMetricReader(OTLPMetricExporter())],
)
metrics.set_meter_provider(meter_provider)

# Shutdown on exit — flushes buffered spans/metrics
atexit.register(tracer_provider.shutdown)
atexit.register(meter_provider.shutdown)
```

> **Logs SDK note:** As of v1.40.0 the Logs SDK is Development status. Suitable for instrumentation tasks; validate stability for production use. `LoggingInstrumentor` (trace context in stdlib records) + `filelog` receiver is the stable ingestion path. See `references/logs.md`.

### 3. LoggingInstrumentor ordering rule (critical)

`LoggingInstrumentor().instrument()` patches `logging.Logger.makeRecord` at the class level and, when `set_logging_format=True`, updates the root logger's handler formatters. It must run **before logging handlers are configured** — before `logging.basicConfig()`, before any framework logging setup (Django's `LOGGING` dict, Gunicorn's log config), and before the application starts emitting records.

Creating a logger with `logging.getLogger()` before calling `instrument()` is **not** the problem — the class-level patch applies to all Logger instances regardless of when they were created. The problem is configuring handlers with formatters that don't include OTel fields before `instrument()` gets a chance to update them.

```python
# BAD — logging.basicConfig() configures a formatter before instrumentation;
# the OTel fields won't appear in that handler's output
import logging
logging.basicConfig(level=logging.INFO)  # formatter locked in here
LoggingInstrumentor().instrument(set_logging_format=True)  # too late to update formatter

# GOOD — instrument first, then configure logging
LoggingInstrumentor().instrument(set_logging_format=True)
import logging
logging.basicConfig(level=logging.INFO)  # formatter includes OTel fields
```

### 4. Environment variables

```bash
# Required — see references/resource-attributes.md to resolve the correct service name
OTEL_SERVICE_NAME=my-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318   # HTTP/protobuf default

# Recommended — spec default is otlp, but Python SDK treats unset as none
OTEL_METRICS_EXPORTER=otlp

# Recommended
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production,service.version=1.2.3

# Optional
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Bearer <token>
OTEL_EXPORTER_OTLP_COMPRESSION=gzip
```

> **Python SDK caveat:** The spec default for `OTEL_METRICS_EXPORTER` is `otlp`, but the Python SDK treats an unset value as `none`. Set `OTEL_METRICS_EXPORTER=otlp` explicitly when using the auto-instrumentation CLI. Manual SDK init does not honor this env var — you must configure `MeterProvider` with a `PeriodicExportingMetricReader` as shown above.

### 5. Post-deploy verification

```bash
tsuga spans search --query "context.service.name:my-service" --max-results 3
tsuga metrics list --filter "service.name=my-service"
tsuga logs search --query "context.service.name:my-service trace_id:*" --max-results 3
```

---

## Path B — Auto-Instrumentation CLI

See `references/auto-instrumentation.md` for full details. Quick summary:

```bash
pip install opentelemetry-distro opentelemetry-exporter-otlp
opentelemetry-bootstrap -a install   # scans installed packages, installs matching instrumentors

OTEL_SERVICE_NAME=my-service \
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 \
OTEL_METRICS_EXPORTER=otlp \
opentelemetry-instrument python app.py
```

`opentelemetry-bootstrap` auto-installs instrumentation for Flask, Django, requests, SQLAlchemy, etc. The `opentelemetry-instrument` wrapper handles TracerProvider and MeterProvider init — no `otel_setup.py` needed.

---

## gRPC opt-in

To use gRPC (port 4317) instead of HTTP/protobuf (port 4318):

```bash
pip install opentelemetry-exporter-otlp-proto-grpc==1.40.0
```

```python
# Replace HTTP imports with gRPC variants
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
```

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317  # no trailing path for gRPC
```

> The Python gRPC exporter requires `http://` scheme (not bare host:port). TLS: use `https://` — the SDK enables TLS automatically.
