# Span Naming, Kind, and Status Rules — Python

> See also: `otel-semantic-conventions` skill for attribute naming; `otel-reference.md` for instrument types.

## Span Naming

**Pattern:** `{verb} {object}` in sentence case. Low-cardinality — no IDs, no raw paths.

| BAD | GOOD | Why |
|-----|------|-----|
| `GET /users/123/orders` | `GET /users/{id}/orders` | Raw path has unbounded cardinality |
| `processOrder` | `process order` | Use space-separated verb-object |
| `db_query` | `SELECT orders` | Include operation and object |
| `kafkaMessage` | `publish shop.orders` | Include system and destination |

```python
# BAD
with tracer.start_as_current_span(f"GET /users/{user_id}/orders") as span:
    ...

# GOOD
with tracer.start_as_current_span("GET /users/{id}/orders") as span:
    span.set_attribute("user.id", user_id)  # ID goes on attribute, not name
    ...
```

## Span Kind Decision Tree

```
Is this span inbound (receiving a request)?
  YES → SERVER

Is this span an outbound synchronous call (HTTP, gRPC, DB)?
  YES → CLIENT

Is this span sending to a queue/topic asynchronously?
  YES → PRODUCER

Is this span consuming from a queue/topic?
  YES → CONSUMER

Is this span local logic only (no network, no I/O)?
  YES → INTERNAL
```

Root spans CANNOT be CLIENT or PRODUCER — a root span with CLIENT kind indicates a missing parent.

```python
from opentelemetry.trace import SpanKind

# Inbound HTTP handler
with tracer.start_as_current_span("POST /orders", kind=SpanKind.SERVER) as span:
    ...

# Outbound HTTP call
with tracer.start_as_current_span("GET products-service", kind=SpanKind.CLIENT) as span:
    ...

# Publishing to Kafka
with tracer.start_as_current_span("publish shop.orders", kind=SpanKind.PRODUCER) as span:
    ...
```

## HTTP Status → Span Status Mapping

**This differs by span kind.** The most common mistake is setting ERROR on SERVER spans for client errors.

| Span Kind | HTTP 2xx | HTTP 4xx | HTTP 5xx |
|-----------|----------|----------|----------|
| SERVER | UNSET | **UNSET** ← server did its job | ERROR |
| CLIENT | UNSET | **ERROR** ← client's problem | ERROR |

**400 Bad Request on a SERVER span is NOT an error.**

```python
from opentelemetry.trace import StatusCode

# SERVER span: 400 is not an error
with tracer.start_as_current_span("POST /orders", kind=SpanKind.SERVER) as span:
    if request.status_code == 400:
        span.set_status(StatusCode.UNSET)  # Client sent bad input; server is fine
    elif request.status_code >= 500:
        span.set_status(StatusCode.ERROR, "Internal server error")

# CLIENT span: 4xx IS an error (the client's call failed)
with tracer.start_as_current_span("GET products-service", kind=SpanKind.CLIENT) as span:
    if response.status_code >= 400:
        span.set_status(StatusCode.ERROR, f"HTTP {response.status_code}")
```

## Headless Operations Pattern

Cron jobs, background tasks, and CLI commands have no inbound HTTP request — no auto-instrumentation creates a root span for them. Create one manually.

```python
# BAD: task function creates child spans with no parent → orphaned spans, invisible in trace UI
def run_nightly_cleanup():
    with tracer.start_as_current_span("query-stale-records") as span:  # Orphan!
        ...

# GOOD: wrap the entire task in a SERVER root span
def run_nightly_cleanup():
    with tracer.start_as_current_span(
        "nightly-cleanup",
        kind=SpanKind.SERVER,
        attributes={"task.name": "nightly-cleanup", "task.trigger": "cron"}
    ) as span:
        with tracer.start_as_current_span("query-stale-records") as child:
            ...
```

## Span Hygiene Rules

- **< 10 INTERNAL spans per trace** — more than 10 INTERNAL spans usually indicates over-instrumentation; consider merging
- **< 20 spans under 5ms** — very short spans add noise without insight
- **No orphan spans** — every span except the root must have a parent
- **Root spans cannot be CLIENT or PRODUCER** — indicates missing trace context propagation
- **Error spans must have a message** — `span.set_status(StatusCode.ERROR, "description")` — the description is required

---

## Span Budget

| Instrument | Recommended |
|---|---|
| Incoming HTTP request | ✅ Always |
| Outgoing HTTP/gRPC call | ✅ Always |
| DB query | ✅ Always |
| External service call | ✅ Always |
| Message queue publish | ✅ Always |
| Message queue consume/process | ✅ Always |
| Internal helper function | ❌ Skip unless genuinely slow or contains meaningful logic |
| Utility called thousands of times per request | ❌ Creates noise and cardinality pressure |
| In-process caching layer (read fast path) | ❌ Skip unless you're debugging cache behavior |

Anti-pattern: instrumenting every method. Prefer minimum spans needed to diagnose failures and latency outliers.

---

## Workflow Boundaries

**Same user operation across services → continue the trace** (propagate W3C `traceparent`)

```python
import requests
from opentelemetry import propagate

headers = {"Content-Type": "application/json"}
propagate.inject(headers)  # injects traceparent into outbound headers
response = requests.post("http://downstream/api/process", headers=headers, json=payload)
```

**Separate operations / separate queue deliveries / separate jobs → new root span**

```python
# Cron job, background worker, CLI — no inbound context
with tracer.start_as_current_span(
    "nightly-cleanup",
    kind=SpanKind.SERVER,  # root span for a headless operation
    attributes={"task.name": "nightly-cleanup", "task.trigger": "cron"},
) as span:
    do_cleanup()
```

**Related but not parent-child → use span Links**

```python
from opentelemetry import propagate, trace

# Async consumer that processes a message from a producer trace
parent_ctx = propagate.extract(message_headers)
parent_span_ctx = trace.get_current_span(parent_ctx).get_span_context()

with tracer.start_as_current_span(
    "process order",
    links=[trace.Link(parent_span_ctx)] if parent_span_ctx.is_valid else [],
) as span:
    process(order)
```

Never propagate a parent context from one unrelated job into another. Misusing parent-child linkage on async consumers inflates producer latency and hides consumer-side errors.

> **→** `references/async-messaging.md` — Kafka/SQS/Celery/RabbitMQ patterns with full semconv.
