# Local Verification — Python

## Overview

Before sending telemetry to a production collector, verify instrumentation locally by routing spans and metrics to stdout. This catches missing spans, incorrect attributes, and SDK misconfiguration without any external infrastructure. For short-lived scripts, explicit shutdown is required or spans will be silently dropped.

## Console Span Exporter

Use `ConsoleSpanExporter` to print every finished span to stdout as JSON.

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import (
    ConsoleSpanExporter,
    SimpleSpanProcessor,
)

provider = TracerProvider()
provider.add_span_processor(SimpleSpanProcessor(ConsoleSpanExporter()))
trace.set_tracer_provider(provider)

tracer = trace.get_tracer("my-service")

with tracer.start_as_current_span("my-operation") as span:
    span.set_attribute("example.key", "value")
    do_work()
```

Each span prints as a structured dict including `trace_id`, `span_id`, `parent_id`, `name`, `attributes`, `status`, and timing.

## Console Metric Exporter

```python
from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import (
    ConsoleMetricExporter,
    PeriodicExportingMetricReader,
)

reader = PeriodicExportingMetricReader(ConsoleMetricExporter(), export_interval_millis=5000)
provider = MeterProvider(metric_readers=[reader])
metrics.set_meter_provider(provider)

meter = metrics.get_meter("my-service")
counter = meter.create_counter("requests.total")
counter.add(1, {"env": "local"})
```

## SimpleSpanProcessor vs BatchSpanProcessor

| | `SimpleSpanProcessor` | `BatchSpanProcessor` |
|---|---|---|
| Export timing | Synchronous, on span end | Async, batched |
| Local testing | Preferred — spans appear immediately | May drop spans if process exits before flush |
| Production | Not recommended — blocks request thread | Correct choice |

Always use `SimpleSpanProcessor` with `ConsoleSpanExporter` during local development. Switch to `BatchSpanProcessor` with an OTLP exporter for production.

## Short-Lived Processes and Scripts

Scripts that exit quickly will lose buffered spans unless `shutdown()` is called explicitly. `SimpleSpanProcessor` is synchronous so it flushes on each span end, but calling `shutdown()` is still required to flush the metric reader and release resources cleanly.

```python
import atexit
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import ConsoleSpanExporter, SimpleSpanProcessor

provider = TracerProvider()
provider.add_span_processor(SimpleSpanProcessor(ConsoleSpanExporter()))
trace.set_tracer_provider(provider)

# Register shutdown so it runs even on unhandled exceptions
atexit.register(provider.shutdown)

tracer = trace.get_tracer("my-script")

with tracer.start_as_current_span("etl.run"):
    process_records()

# Explicit call for scripts where atexit may not fire (e.g., sys.exit)
provider.shutdown()
```

## OTEL_TRACES_EXPORTER=console Environment Variable

Python's OTel SDK natively supports the `OTEL_TRACES_EXPORTER=console` environment variable. Set it alongside `opentelemetry-instrument` (auto-instrumentation) or when configuring the SDK via environment.

```bash
OTEL_TRACES_EXPORTER=console \
OTEL_SERVICE_NAME=my-service \
opentelemetry-instrument python app.py
```

This replaces any OTLP exporter with `ConsoleSpanExporter` without changing application code — useful for quick triage in any environment where you can set env vars.

The `http://` scheme prefix in `OTLPSpanExporter(endpoint="http://localhost:4317")` is required for the Python gRPC exporter — unlike the Go SDK, it parses a full URI rather than `host:port`. Omitting `http://` causes a silent connection failure.

## Local Collector with Debug Exporter

Run `otelcol-contrib` locally to validate the full OTLP pipeline. The `debug` exporter prints every received span and metric to the collector's stdout with full attribute detail.

```yaml
# otelcol-config.yaml — local debug collector
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

exporters:
  debug:
    verbosity: detailed

service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [debug]
    metrics:
      receivers: [otlp]
      exporters: [debug]
```

Start the collector and point your application at it:

```bash
otelcol-contrib --config otelcol-config.yaml

OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
OTEL_SERVICE_NAME=my-service \
python app.py
```
