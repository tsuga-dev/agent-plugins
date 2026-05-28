# Distributed Context Propagation — Python

## Overview

Trace context must be explicitly propagated across service boundaries. The W3C TraceContext headers (`traceparent`, `tracestate`) carry the trace ID and span ID between services. With auto-instrumentation, HTTP propagation is handled automatically. For manual setups and message queues, explicit extract/inject calls are needed.

## Inbound: Server Context Extraction

**Auto-instrumentation (Flask, FastAPI, Django):** Fully automatic. The instrumentor reads `traceparent` from incoming request headers and creates a child span for the request.

**Manual extraction:**

```python
from opentelemetry import trace, propagate
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

# Generic extraction from a dict-like headers object
def extract_context(headers: dict):
    ctx = propagate.extract(headers)
    return ctx

# In a raw HTTP handler (e.g., with http.server)
def handle_request(request):
    # request.headers is a dict-like object
    parent_ctx = propagate.extract(dict(request.headers))

    tracer = trace.get_tracer("my-service")
    with tracer.start_as_current_span("handle.request", context=parent_ctx) as span:
        span.set_attribute("http.method", request.method)
        do_work()
```

## Outbound: Client Context Injection

**Auto-instrumentation (`requests`, `httpx`):** Automatic. The instrumentor injects `traceparent` into outgoing request headers.

**Manual injection with `requests`:**

```python
import requests
from opentelemetry import propagate

def call_downstream(url: str):
    headers = {"Content-Type": "application/json"}
    # Inject current active context into headers dict
    propagate.inject(headers)

    # headers now contains traceparent (and tracestate if set)
    response = requests.get(url, headers=headers)
    return response.json()
```

**Manual injection with `httpx`:**

```python
import httpx
from opentelemetry import propagate

async def call_downstream_async(url: str):
    headers = {}
    propagate.inject(headers)

    async with httpx.AsyncClient() as client:
        response = await client.get(url, headers=headers)
    return response.json()
```

**gRPC client injection:**

```python
import grpc
from opentelemetry import propagate
from opentelemetry.instrumentation.grpc import GrpcInstrumentorClient

# Option A: auto-instrumentation (recommended)
GrpcInstrumentorClient().instrument()

# Option B: manual interceptor
class OtelClientInterceptor(grpc.UnaryUnaryClientInterceptor):
    def intercept_unary_unary(self, continuation, client_call_details, request):
        metadata = list(client_call_details.metadata or [])
        carrier = {}
        propagate.inject(carrier)
        for k, v in carrier.items():
            metadata.append((k, v))

        new_details = client_call_details._replace(metadata=metadata)
        return continuation(new_details, request)
```

In the manual interceptor, `propagate.inject` writes into a plain `dict`, and the interceptor then converts each key-value pair into a tuple appended to the gRPC metadata list — this conversion step is necessary because gRPC metadata does not implement the dict interface that OTel's carrier protocol requires.

## Message Queue Propagation

For Kafka, SQS, Celery, and RabbitMQ propagation patterns — including producer inject, consumer extract, span Links rule, and full `messaging.*` semconv attributes — see `references/async-messaging.md`.

## Anti-Pattern: Do Not Merge Separate Workflows

```python
from opentelemetry import trace

tracer = trace.get_tracer("my-service")

# WRONG — child span merges background job into HTTP request trace
with tracer.start_as_current_span("process.job", context=extracted_ctx) as span:
    ...

# CORRECT — new root span, linked to producer trace
parent_span_ctx = trace.get_current_span(extracted_ctx).get_span_context()
with tracer.start_as_current_span(
    "process.job",
    links=[trace.Link(parent_span_ctx)],
) as span:
    ...
```

## Configuring Propagators

The default propagator is W3C TraceContext + Baggage. To add B3:

```bash
OTEL_PROPAGATORS=tracecontext,baggage,b3multi
```

Programmatically:

```python
from opentelemetry.propagate import set_global_textmap
from opentelemetry.propagators.composite import CompositePropagator
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator
from opentelemetry.propagators.b3 import B3MultiFormat

set_global_textmap(CompositePropagator([
    TraceContextTextMapPropagator(),
    B3MultiFormat(),
]))
```

## Tsuga Trace Continuity Validation

```bash
tsuga spans search --query "context.service.name:<caller-service>" --max-results 5
# Note traceId
tsuga spans search --query "context.service.name:<callee-service> traceId:<trace-id>"
# parentSpanId on callee spans must match spanId from caller
```
