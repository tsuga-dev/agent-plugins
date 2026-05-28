# Framework-Specific Recipes — Python

## FastAPI

```bash
pip install opentelemetry-instrumentation-fastapi opentelemetry-instrumentation-httpx
```

```python
# otel_setup.py
from opentelemetry import trace, metrics
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor

resource = Resource.create({
    "service.name": "fastapi-service",
    "deployment.environment.name": "production",
})

tracer_provider = TracerProvider(resource=resource)
tracer_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
trace.set_tracer_provider(tracer_provider)

meter_provider = MeterProvider(
    resource=resource,
    metric_readers=[PeriodicExportingMetricReader(OTLPMetricExporter())],
)
metrics.set_meter_provider(meter_provider)

# Instrument before creating the app
HTTPXClientInstrumentor().instrument()
```

```python
# main.py
import otel_setup  # import FIRST

from fastapi import FastAPI, HTTPException, Request
from opentelemetry import trace
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

app = FastAPI()
FastAPIInstrumentor.instrument_app(
    app,
    excluded_urls="/health,/metrics",
)

tracer = trace.get_tracer("fastapi-service")

@app.get("/users/{user_id}")
async def get_user(user_id: str, request: Request):
    with tracer.start_as_current_span("db.get_user") as span:
        span.set_attribute("user.id", user_id)
        user = await fetch_user_from_db(user_id)
        if not user:
            span.set_attribute("user.found", False)
            raise HTTPException(status_code=404, detail="User not found")
        return user

@app.get("/health")
async def health():
    return {"status": "ok"}
```

## Django

```bash
pip install opentelemetry-instrumentation-django opentelemetry-instrumentation-requests
```

```python
# manage.py or wsgi.py / asgi.py — before Django setup
import otel_setup  # must be imported before django.setup()

# settings.py
OTEL_DJANGO_EXCLUDED_URLS = "health,metrics,admin"
```

```python
# apps.py (recommended placement for Django)
from django.apps import AppConfig

class MyAppConfig(AppConfig):
    name = "myapp"

    def ready(self):
        from opentelemetry.instrumentation.django import DjangoInstrumentor
        from opentelemetry.instrumentation.requests import RequestsInstrumentor

        DjangoInstrumentor().instrument(
            excluded_urls="health,metrics",
        )
        RequestsInstrumentor().instrument()
```

```python
# views.py
from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode
from django.http import JsonResponse

tracer = trace.get_tracer("django-service")

def get_user(request, user_id):
    with tracer.start_as_current_span("db.get_user") as span:
        span.set_attribute("user.id", user_id)
        try:
            user = User.objects.get(id=user_id)
            return JsonResponse({"id": user.id, "email": user.email})
        except User.DoesNotExist:
            span.set_status(Status(StatusCode.ERROR, "user not found"))
            return JsonResponse({"error": "not found"}, status=404)
```

## Flask

```bash
pip install opentelemetry-instrumentation-flask opentelemetry-instrumentation-sqlalchemy
```

```python
# app.py
import otel_setup  # FIRST

from flask import Flask, jsonify
from opentelemetry import trace
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor

FlaskInstrumentor().instrument(excluded_urls="/health")

app = Flask(__name__)

# SQLAlchemy instrumented after engine creation
from sqlalchemy import create_engine
engine = create_engine(DATABASE_URL)
SQLAlchemyInstrumentor().instrument(engine=engine)

tracer = trace.get_tracer("flask-service")

@app.route("/users/<user_id>")
def get_user(user_id):
    with tracer.start_as_current_span("business.get_user") as span:
        span.set_attribute("user.id", user_id)
        # SQLAlchemy queries inside here get their own child spans automatically
        user = db.session.get(User, user_id)
        if not user:
            return jsonify({"error": "not found"}), 404
        return jsonify(user.to_dict())

@app.route("/health")
def health():
    return jsonify({"status": "ok"})
```

## SQLAlchemy

Auto-instrumented via `opentelemetry-instrumentation-sqlalchemy`. Each SQL query becomes a span with `db.statement` attribute.

```python
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session

engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    pool_size=10,
)

# Instrument the engine — creates db spans for all queries
SQLAlchemyInstrumentor().instrument(
    engine=engine,
    enable_commenter=True,  # adds otel trace context to SQL comments
)

# Usage — query spans appear as children of the active span
with Session(engine) as session:
    result = session.execute(text("SELECT * FROM users WHERE id = :id"), {"id": user_id})
    return result.fetchone()
```

## Async (asyncio / FastAPI / Starlette)

For async frameworks, use async-compatible instrumentors and always `await` async operations inside spans:

```python
from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode

tracer = trace.get_tracer("async-service")

async def process_request(user_id: str):
    with tracer.start_as_current_span("process.request") as span:
        span.set_attribute("user.id", user_id)
        try:
            # Async calls propagate context via contextvars (Python 3.7+)
            result = await fetch_data(user_id)
            additional = await enrich_data(result)
            span.set_attribute("result.count", len(additional))
            return additional
        except Exception as e:
            span.record_exception(e)
            span.set_status(Status(StatusCode.ERROR, str(e)))
            raise
```

> Python's `contextvars.ContextVar` (used internally by OTel) propagates automatically across `await` boundaries in async functions — no special action needed.

## Lifecycle Logging

Structured log events correlated with OTel trace context — essential for microservice observability.

```python
import logging
import os
import json
from opentelemetry import trace

# Structured JSON logger
class JsonFormatter(logging.Formatter):
    def format(self, record):
        span = trace.get_current_span()
        ctx = span.get_span_context()
        log = {
            "timestamp": self.formatTime(record),
            "level": record.levelname,
            "message": record.getMessage(),
            "service": os.getenv("OTEL_SERVICE_NAME", "unknown"),
        }
        if ctx.is_valid:
            log["trace_id"] = format(ctx.trace_id, "032x")
            log["span_id"] = format(ctx.span_id, "016x")
        if record.exc_info:
            log["exception"] = self.formatException(record.exc_info)
        return json.dumps(log)

logging.getLogger().handlers[0].setFormatter(JsonFormatter())
logger = logging.getLogger(__name__)

# --- Service startup ---
def on_startup():
    logger.info("service starting", extra={
        "version": os.getenv("APP_VERSION", "unknown"),
        "environment": os.getenv("DEPLOYMENT_ENV", "unknown"),
        "otel_endpoint": os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "not set"),
    })

# --- Request lifecycle (FastAPI example) ---
@app.middleware("http")
async def log_requests(request: Request, call_next):
    logger.info("request received", extra={
        "method": request.method,
        "path": request.url.path,
    })
    response = await call_next(request)
    logger.info("request completed", extra={
        "method": request.method,
        "path": request.url.path,
        "status_code": response.status_code,
    })
    return response

# --- Graceful shutdown ---
def on_shutdown():
    logger.info("service shutting down")
    tracer_provider.shutdown()
    meter_provider.shutdown()
    logger.info("otel providers shut down")
```

> The `trace_id` and `span_id` are injected automatically from the active OTel span — no manual wiring needed once the formatter is in place.

## Microservices Propagation Pattern

Two-service HTTP call: caller injects trace context, callee extracts and creates a child span.

**Caller service (outbound HTTP with httpx):**

```python
# Automatic with HTTPXClientInstrumentor — no manual inject needed
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
HTTPXClientInstrumentor().instrument()  # all httpx calls auto-inject W3C headers

import httpx
from opentelemetry import trace

tracer = trace.get_tracer("caller-service")

async def call_downstream(user_id: str) -> dict:
    with tracer.start_as_current_span("call.user-service") as span:
        span.set_attribute("user.id", user_id)
        async with httpx.AsyncClient() as client:
            # W3C traceparent + tracestate injected automatically
            response = await client.get(f"http://user-service/users/{user_id}")
            span.set_attribute("http.status_code", response.status_code)
            return response.json()
```

**Callee service (inbound HTTP with FastAPI):**

```python
# FastAPIInstrumentor extracts W3C headers and creates a child span automatically
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
FastAPIInstrumentor.instrument_app(app)

# The incoming request's traceparent header is parsed — the handler span is a child
# of the caller's span, creating a continuous trace across services.

@app.get("/users/{user_id}")
async def get_user(user_id: str):
    # This span is automatically a child of the caller's span
    return {"id": user_id, "name": "Alice"}
```

**Manual inject/extract** (if not using auto-instrumentation):

```python
from opentelemetry.propagate import inject, extract

# Caller — inject into headers dict
headers = {}
inject(headers)
response = requests.get("http://user-service/users/123", headers=headers)

# Callee — extract from incoming headers
context = extract(request.headers)
with tracer.start_as_current_span("handle.request", context=context) as span:
    # span is a child of the upstream trace
    ...
```

**Validate in Tsuga:** Use `tsuga spans search --service caller-service` and confirm the upstream span's `trace_id` matches the downstream span's `trace_id`.
