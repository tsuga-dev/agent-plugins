# Span Naming, Kind, and Status Rules — Java

> See also: `otel-semantic-conventions` skill for attribute naming; `otel-reference.md` for instrument types.

## Span Naming

**Pattern:** `{verb} {object}` in sentence case. Low-cardinality — no IDs, no raw paths.

| BAD | GOOD | Why |
|-----|------|-----|
| `GET /users/123/orders` | `GET /users/{id}/orders` | Raw path has unbounded cardinality |
| `processOrder` | `process order` | Use space-separated verb-object |
| `dbQuery` | `SELECT orders` | Include operation and object |

```java
// BAD
Span span = tracer.spanBuilder("GET /users/" + userId + "/orders").startSpan();

// GOOD
Span span = tracer.spanBuilder("GET /users/{id}/orders")
    .setAttribute("user.id", userId)
    .startSpan();
```

## Span Kind Decision Tree

| Scenario | Kind |
|----------|------|
| Inbound HTTP/gRPC handler | `SpanKind.SERVER` |
| Outbound HTTP, gRPC, DB call | `SpanKind.CLIENT` |
| Publishing to Kafka/SQS/RabbitMQ | `SpanKind.PRODUCER` |
| Consuming from queue | `SpanKind.CONSUMER` |
| Local method (no I/O) | `SpanKind.INTERNAL` |

```java
import io.opentelemetry.api.trace.SpanKind;

// Inbound
Span span = tracer.spanBuilder("POST /orders")
    .setSpanKind(SpanKind.SERVER)
    .startSpan();

// Outbound
Span span = tracer.spanBuilder("GET products-service")
    .setSpanKind(SpanKind.CLIENT)
    .startSpan();
```

## HTTP Status → Span Status Mapping

| Span Kind | HTTP 4xx | HTTP 5xx |
|-----------|----------|----------|
| SERVER | **UNSET** (server did its job) | ERROR |
| CLIENT | **ERROR** (call failed) | ERROR |

```java
import io.opentelemetry.api.trace.StatusCode;

// Server span: 400 is NOT an error
if (statusCode >= 500) {
    span.setStatus(StatusCode.ERROR, "Internal server error");
}
// 4xx on server: leave as default UNSET

// Client span: 4xx IS an error
if (statusCode >= 400) {
    span.setStatus(StatusCode.ERROR, "HTTP " + statusCode);
}
```

## Headless Operations Pattern

```java
// BAD: @Scheduled method has no parent span context → orphan child spans
@Scheduled(cron = "0 0 * * * *")
public void nightlyCleanup() {
    Span child = tracer.spanBuilder("query-stale-records").startSpan();  // Orphan!
}

// GOOD: create SERVER root span wrapping the entire task
@Scheduled(cron = "0 0 * * * *")
public void nightlyCleanup() {
    Span rootSpan = tracer.spanBuilder("nightly-cleanup")
        .setSpanKind(SpanKind.SERVER)
        .setAttribute("task.name", "nightly-cleanup")
        .setAttribute("task.trigger", "cron")
        .startSpan();
    try (Scope scope = rootSpan.makeCurrent()) {
        Span child = tracer.spanBuilder("query-stale-records").startSpan();
        try (Scope childScope = child.makeCurrent()) {
            // work
        } finally {
            child.end();
        }
    } finally {
        rootSpan.end();
    }
}
```

## Span Hygiene Rules

- **< 10 INTERNAL spans per trace** — more indicates over-instrumentation
- **< 20 spans under 5ms** — short spans add noise
- **No orphan spans** — every span except root must have a parent
- **Root spans cannot be CLIENT or PRODUCER**
- **Error spans must have a description** — `span.setStatus(StatusCode.ERROR, "description")`

## Span Budget

| Operation type | Instrument? | Notes |
|----------------|-------------|-------|
| Incoming HTTP request | ✅ Always | Agent covers this automatically |
| Outgoing HTTP / gRPC call | ✅ Always | Agent covers this automatically |
| DB query | ✅ Always | Agent covers JDBC automatically |
| External service call | ✅ Always | — |
| Business transaction (order.place, payment.charge) | ✅ Yes | Use `@WithSpan` or manual span |
| Internal helper function | ❌ Skip | Unless measurably slow or failure-prone |
| Utility called thousands of times per request | ❌ Skip | Creates noise; use metric instead |
| Loop iteration (per-item span in a batch) | ⚠️ Only if needed | Confirm sampling is in place first |

Anti-pattern: instrumenting every method. The span budget goal is minimum spans needed to diagnose failures and measure latency at service boundaries.

## Workflow Boundaries

**Rule:** Same user operation across services → continue the trace (propagate W3C `traceparent`). Separate operations, separate queue deliveries, or separate scheduled jobs → new root span.

Never propagate a parent context from one unrelated job into another.

### Continue the trace (outbound call)

```java
// Inject current context into outbound HTTP headers
TextMapSetter<HttpGet> setter = (carrier, key, value) -> carrier.setHeader(key, value);
HttpGet request = new HttpGet("https://downstream-service/api");
GlobalOpenTelemetry.getPropagators()
    .getTextMapPropagator()
    .inject(Context.current(), request, setter);
```

### New root span (scheduled job or batch)

```java
// setNoParent() creates a true root — no inherited parent context
Span rootSpan = tracer.spanBuilder("nightly-cleanup")
    .setNoParent()
    .setSpanKind(SpanKind.SERVER)
    .setAttribute("task.name", "nightly-cleanup")
    .setAttribute("task.trigger", "cron")
    .startSpan();
try (Scope scope = rootSpan.makeCurrent()) {
    doWork();
} finally {
    rootSpan.end();
}
```

### Related but not parent-child (async / queue)

```java
// addLink() connects traces for navigation without making one a child of the other
Span span = tracer.spanBuilder("process order")
    .setNoParent()
    .addLink(producerSpanContext)   // link to producer trace
    .setSpanKind(SpanKind.CONSUMER)
    .startSpan();
```

> **→** `references/async-messaging.md` — full Kafka, JMS, SQS, RabbitMQ patterns with semconv.
