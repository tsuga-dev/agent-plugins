# Logs and Trace-Log Correlation — Python OTel

> **Last verified:** 2026-03-23 | SDK: `opentelemetry-instrumentation-logging` 0.61b0

**Logs SDK status:** Python Logs API and SDK are Development status. Suitable for instrumentation tasks; validate stability for your production use case. The `filelog` receiver path (stdout JSON → Collector) is the stable alternative when log ingestion reliability is critical.

---

## Decision: Which logging path to use

| Scenario | Path |
|----------|------|
| Task says "logs to endpoint", "OTLP logs", "log export to collector" | **Option A — LoggerProvider + OTLPLogExporter** |
| Using stdlib `logging` (or any framework that delegates to it) | **Option B — LoggingInstrumentor** |
| Need manual control or LoggingInstrumentor unavailable | **Option C — TraceContextFilter** |
| Using structlog for rich processor chains | **Option D — structlog processor** |
| Need stable production log ingestion via Collector | **Option E — filelog receiver** |

> **Options B–E only inject trace context into log records — they do NOT send logs to the OTLP endpoint.** Use Option A when the task explicitly requires logs at the collector.

---

## Option A — LoggerProvider + OTLPLogExporter (send logs to collector)

Use when the task requires log records to be shipped to the OTLP endpoint.

```bash
pip install opentelemetry-sdk==1.40.0 \
            opentelemetry-exporter-otlp-proto-http==1.40.0 \
            opentelemetry-instrumentation-logging==0.61b0
```

```python
from opentelemetry.sdk._logs import LoggerProvider
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
from opentelemetry._logs import set_logger_provider
from opentelemetry.instrumentation.logging import LoggingInstrumentor

# 1. Create the LoggerProvider — use the same resource as TracerProvider/MeterProvider
logger_provider = LoggerProvider(resource=resource)

# 2. Wire the OTLP exporter — reads OTEL_EXPORTER_OTLP_ENDPOINT automatically
logger_provider.add_log_record_processor(
    BatchLogRecordProcessor(OTLPLogExporter())
)
set_logger_provider(logger_provider)

# 3. Bridge: connect stdlib logging records into the OTel log pipeline
#    Call BEFORE any logging.basicConfig() or framework logging setup
LoggingInstrumentor().instrument(set_logging_format=True)
```

This sends log records to `OTEL_EXPORTER_OTLP_ENDPOINT/v1/logs` (default: `http://localhost:4318/v1/logs`).

> **Option A + Option B together:** `OTLPLogExporter` exports log records. `LoggingInstrumentor` (step 3) injects `trace_id`/`span_id` into each record so logs correlate with traces. Both are usually needed.

---

## Option B — `LoggingInstrumentor` (recommended)

Patches Python's stdlib `logging` module globally to inject `otelTraceID` and `otelSpanID` into every `LogRecord`. Works with any handler that uses stdlib `logging` under the hood (including Django, Flask, Celery worker logs).

### Critical ordering rule

`LoggingInstrumentor().instrument()` patches `logging.Logger.makeRecord` at the **class level**, so all Logger instances — past and future — are covered regardless of when `logging.getLogger()` was called. Creating a logger before calling `instrument()` is **not** the problem.

The actual constraint: call `instrument()` **before logging handlers are configured** — before `logging.basicConfig()`, before any framework logging setup (Django `LOGGING`, Gunicorn log config), and before the application starts emitting records. If handlers already have formatters set, `set_logging_format=True` will update them, but the safest position is first in the startup sequence.

```python
# BAD — basicConfig() locks in a formatter before instrumentation can update it
import logging
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
from opentelemetry.instrumentation.logging import LoggingInstrumentor
LoggingInstrumentor().instrument(set_logging_format=True)  # formatter already set

# GOOD — instrument before any logging configuration
from opentelemetry.instrumentation.logging import LoggingInstrumentor
LoggingInstrumentor().instrument(set_logging_format=True)
import logging
logging.basicConfig(level=logging.INFO)  # formatter now includes OTel fields
```

### Setup

```bash
pip install opentelemetry-instrumentation-logging==0.61b0
```

```python
# In otel_setup.py — FIRST thing before any other imports
from opentelemetry.instrumentation.logging import LoggingInstrumentor
LoggingInstrumentor().instrument(set_logging_format=True)
```

After instrumentation, every log record includes:

```
INFO 2026-03-23 12:00:00 [my_module] [trace_id=abc123 span_id=def456 resource.service.name=my-service] User logged in
```

### Does not affect

`LoggingInstrumentor` does NOT affect `structlog`, `loguru`, or other third-party loggers unless they delegate to stdlib `logging` handlers internally.

---

## Option C — Manual `TraceContextFilter`

For cases where `LoggingInstrumentor` is not available or you need custom field names.

```python
import logging
from opentelemetry import trace

class TraceContextFilter(logging.Filter):
    def filter(self, record):
        span = trace.get_current_span()
        ctx = span.get_span_context()
        record.trace_id = format(ctx.trace_id, "032x") if ctx.is_valid else ""
        record.span_id  = format(ctx.span_id, "016x") if ctx.is_valid else ""
        return True

# Apply to root logger
handler = logging.StreamHandler()
handler.addFilter(TraceContextFilter())
handler.setFormatter(logging.Formatter(
    '{"level": "%(levelname)s", "message": "%(message)s", '
    '"trace_id": "%(trace_id)s", "span_id": "%(span_id)s"}'
))
logging.getLogger().addHandler(handler)
logging.getLogger().setLevel(logging.INFO)
```

---

## Option D — structlog

Use when you have an existing structlog setup or need rich processor chains.

```python
import structlog
from opentelemetry import trace

def add_trace_context(logger, method, event_dict):
    span = trace.get_current_span()
    ctx = span.get_span_context()
    if ctx.is_valid:
        event_dict["trace_id"] = format(ctx.trace_id, "032x")
        event_dict["span_id"]  = format(ctx.span_id, "016x")
    return event_dict

structlog.configure(processors=[
    add_trace_context,
    structlog.processors.add_log_level,
    structlog.processors.TimeStamper(fmt="iso"),
    structlog.processors.JSONRenderer(),
])

logger = structlog.get_logger()
```

---

## Option E — filelog Collector receiver (production path)

The stable production alternative for log ingestion: emit JSON to stdout, let the Collector's `filelog` receiver pick it up and forward via OTLP.

```bash
pip install python-json-logger
```

Add a `TraceContextFilter` (Option B) **before** setting the formatter — the formatter references `%(trace_id)s` and `%(span_id)s` fields that only exist once the filter has populated them on each record.

```python
import logging
import sys
from opentelemetry import trace
from pythonjsonlogger import jsonlogger

# Step 1 — filter that injects trace_id and span_id onto each LogRecord
class TraceContextFilter(logging.Filter):
    def filter(self, record):
        span = trace.get_current_span()
        ctx = span.get_span_context()
        record.trace_id = format(ctx.trace_id, "032x") if ctx.is_valid else ""
        record.span_id  = format(ctx.span_id, "016x") if ctx.is_valid else ""
        return True

# Step 2 — handler with JSON formatter that references those fields
handler = logging.StreamHandler(sys.stdout)
handler.addFilter(TraceContextFilter())
handler.setFormatter(jsonlogger.JsonFormatter(
    fmt="%(asctime)s %(levelname)s %(name)s %(message)s %(trace_id)s %(span_id)s"
))
logging.getLogger().addHandler(handler)
logging.getLogger().setLevel(logging.INFO)
```

Configure the Collector `filelog` receiver to read stdout — see `otel-collector` skill.

---

## Logger choice

| Use | When |
|-----|------|
| stdlib `logging` | No existing logging setup; want simplest OTel integration |
| structlog | Already using structlog; need rich processor chains; want typed log events |
| python-json-logger + filelog | Production log ingestion when Logs SDK is not yet stable |

---

## Verification

```bash
# Confirm trace IDs appear in log records
tsuga logs search --query "context.service.name:my-service trace_id:*" --max-results 3

# If 0 results:
# → tsuga-debug-no-data (pipeline issue)
# → tsuga-debug-missing-trace-propagation (correlation issue)
```
