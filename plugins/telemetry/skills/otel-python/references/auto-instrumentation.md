# Auto-Instrumentation — Python

## Overview

Python OTel provides two auto-instrumentation mechanisms:
1. **`opentelemetry-bootstrap`** — scans installed packages and installs matching instrumentation libraries
2. **`opentelemetry-instrument`** — a CLI wrapper that loads all installed instrumentations at startup via the `sitecustomize.py` mechanism

Both mechanisms require the `opentelemetry-distro` package.

## Installation

```bash
pip install opentelemetry-distro opentelemetry-exporter-otlp
# Scan installed packages and install matching instrumentation:
opentelemetry-bootstrap -a install
```

`opentelemetry-bootstrap` reads your installed packages (from `pip list`) and installs the appropriate `opentelemetry-instrumentation-*` packages. Run it after installing your app dependencies.

## Zero-Code Startup

```bash
opentelemetry-instrument \
  --service-name my-service \
  --exporter-otlp-endpoint http://localhost:4318 \
  python app.py
```

Or via environment variables (recommended for production):

```bash
OTEL_SERVICE_NAME=my-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318   # HTTP/protobuf (recommended default)
OTEL_TRACES_EXPORTER=otlp
OTEL_METRICS_EXPORTER=otlp
OTEL_LOGS_EXPORTER=otlp

opentelemetry-instrument python app.py
```

> **gRPC alternative:** To use gRPC instead of HTTP/protobuf, set `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317` and `OTEL_EXPORTER_OTLP_PROTOCOL=grpc`. The rest of this skill defaults to HTTP/protobuf (port 4318). See `references/quickstart.md` for gRPC setup details.

## What Gets Covered Automatically

| Library | Instrumentation package |
|---|---|
| Flask | `opentelemetry-instrumentation-flask` |
| Django | `opentelemetry-instrumentation-django` |
| FastAPI | `opentelemetry-instrumentation-fastapi` |
| Starlette | `opentelemetry-instrumentation-starlette` |
| requests | `opentelemetry-instrumentation-requests` |
| httpx | `opentelemetry-instrumentation-httpx` |
| aiohttp | `opentelemetry-instrumentation-aiohttp-client` |
| SQLAlchemy | `opentelemetry-instrumentation-sqlalchemy` |
| psycopg2 | `opentelemetry-instrumentation-psycopg2` |
| pymongo | `opentelemetry-instrumentation-pymongo` |
| redis | `opentelemetry-instrumentation-redis` |
| celery | `opentelemetry-instrumentation-celery` |
| grpc | `opentelemetry-instrumentation-grpc` |
| boto3 / botocore | `opentelemetry-instrumentation-botocore` |
| logging | `opentelemetry-instrumentation-logging` |

## Programmatic Activation (without `opentelemetry-instrument`)

```python
# otel_setup.py — import BEFORE app modules
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from opentelemetry.instrumentation.logging import LoggingInstrumentor

# Call instrument() BEFORE creating app/engine instances
FlaskInstrumentor().instrument()
RequestsInstrumentor().instrument()
LoggingInstrumentor().instrument(set_logging_format=True)
# SQLAlchemy: pass engine after creation
```

```python
# app.py
from flask import Flask
app = Flask(__name__)

# SQLAlchemy after engine creation
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from sqlalchemy import create_engine
engine = create_engine(DATABASE_URL)
SQLAlchemyInstrumentor().instrument(engine=engine)
```

> **Critical:** Call `.instrument()` before creating instances of the instrumented library (Flask app, SQLAlchemy engine, etc.). For `FlaskInstrumentor`, `instrument()` replaces the `flask.Flask` class, so it must run before `Flask()` is instantiated — importing Flask first is fine. Alternatively, use `instrument_app(app)` to instrument an existing app instance.

## Configuring Individual Instrumentors

```python
from opentelemetry.instrumentation.flask import FlaskInstrumentor

FlaskInstrumentor().instrument(
    # Exclude health check endpoint from tracing
    excluded_urls="/health,/metrics,/ready",
    # Request hook — add custom attributes to server spans
    request_hook=lambda span, environ: span.set_attribute(
        "http.client_ip", environ.get("REMOTE_ADDR", "")
    ),
)
```

```python
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor

SQLAlchemyInstrumentor().instrument(
    engine=engine,
    # Capture full SQL statement (disabled by default)
    enable_commenter=True,
)
```

## What Needs Manual Instrumentation

Auto-instrumentation does not cover:

- Business logic spans (e.g., `order.validate`, `pricing.compute`)
- Celery task internals — the instrumentation creates a task span, but subtasks need manual spans
- Background threads or async tasks not using a supported framework
- Custom protocols or message formats

For manual spans alongside auto-instrumentation:

```python
from opentelemetry import trace

tracer = trace.get_tracer("my-service")

@app.route("/checkout")
def checkout():
    with tracer.start_as_current_span("order.process") as span:
        span.set_attribute("cart.items", len(cart))
        result = process_order(cart)
        span.set_attribute("order.id", result.id)
        return jsonify(result)
```

## LoggingInstrumentor Ordering

`LoggingInstrumentor().instrument()` patches `logging.Logger.makeRecord` at the **class level**, so all Logger instances — past and future — are affected. Creating a logger with `logging.getLogger()` before calling `instrument()` is **not** the problem. The real constraint is that `instrument()` must run **before logging handlers are configured** (before `logging.basicConfig()`, before framework logging setup) so that `set_logging_format=True` can update handler formatters to include OTel fields.

```python
# BAD — basicConfig() locks in a formatter before instrumentation can update it
import logging
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
LoggingInstrumentor().instrument(set_logging_format=True)  # formatter already set

# GOOD — instrument before any logging configuration
from opentelemetry.instrumentation.logging import LoggingInstrumentor
LoggingInstrumentor().instrument(set_logging_format=True)

import logging
logging.basicConfig(level=logging.INFO)  # formatter now includes OTel fields
```

## Verifying Auto-Instrumentation Is Active

```bash
# Make a request, then check Tsuga:
tsuga spans search --query "context.service.name:my-service" --max-results 5
# Look for spans like "GET /path", "SELECT ...", "redis.get"
```
