# Span Naming, Kind, and Status Rules — Go

> See also: `otel-semantic-conventions` skill for attribute naming; `otel-reference.md` for instrument types.

## Span Naming

**Pattern:** `{verb} {object}` in sentence case. Low-cardinality — no IDs, no raw paths.

| BAD | GOOD | Why |
|-----|------|-----|
| `GET /users/123/orders` | `GET /users/{id}/orders` | Raw path has unbounded cardinality |
| `processOrder` | `process order` | Use space-separated verb-object |
| `dbQuery` | `SELECT orders` | Include operation and object |
| `kafkaMessage` | `publish shop.orders` | Include system and destination |

```go
// BAD
ctx, span := tracer.Start(ctx, fmt.Sprintf("GET /users/%s/orders", userID))

// GOOD
ctx, span := tracer.Start(ctx, "GET /users/{id}/orders")
span.SetAttributes(attribute.String("user.id", userID))  // ID goes on attribute
defer span.End()
```

## Span Kind Decision Tree

```
Is this span inbound (receiving a request)?  → trace.SpanKindServer
Is this span an outbound sync call?          → trace.SpanKindClient
Is this span sending to a queue/topic async? → trace.SpanKindProducer
Is this span consuming from a queue/topic?   → trace.SpanKindConsumer
Is this span local logic only?               → trace.SpanKindInternal
```

Root spans CANNOT be SpanKindClient or SpanKindProducer.

```go
import "go.opentelemetry.io/otel/trace"

// Inbound handler
ctx, span := tracer.Start(ctx, "POST /orders", trace.WithSpanKind(trace.SpanKindServer))

// Outbound HTTP
ctx, span := tracer.Start(ctx, "GET products-service", trace.WithSpanKind(trace.SpanKindClient))

// Kafka publish
ctx, span := tracer.Start(ctx, "publish shop.orders", trace.WithSpanKind(trace.SpanKindProducer))
```

## HTTP Status → Span Status Mapping

| Span Kind | HTTP 2xx | HTTP 4xx | HTTP 5xx |
|-----------|----------|----------|----------|
| SpanKindServer | UNSET | **UNSET** | ERROR |
| SpanKindClient | UNSET | **ERROR** | ERROR |

**400 Bad Request on a Server span is NOT an error.**

```go
import "go.opentelemetry.io/otel/codes"

// Server span
if statusCode >= 500 {
    span.SetStatus(codes.Error, "internal server error")
} // 4xx on server: leave as UNSET (codes.Unset is the default)

// Client span
if statusCode >= 400 {
    span.SetStatus(codes.Error, fmt.Sprintf("HTTP %d", statusCode))
}
```

## Headless Operations Pattern

```go
// BAD: child spans with no parent → orphaned
func runNightlyCleanup(ctx context.Context) {
    ctx, span := tracer.Start(ctx, "query-stale-records")  // Orphan if ctx has no parent!
    defer span.End()
}

// GOOD: create root span explicitly
func runNightlyCleanup() {
    ctx, rootSpan := tracer.Start(context.Background(), "nightly-cleanup",
        trace.WithSpanKind(trace.SpanKindServer),
        trace.WithAttributes(
            attribute.String("task.name", "nightly-cleanup"),
            attribute.String("task.trigger", "cron"),
        ),
    )
    defer rootSpan.End()

    ctx, child := tracer.Start(ctx, "query-stale-records")
    defer child.End()
}
```

## Span Hygiene Rules

- **< 10 INTERNAL spans per trace** — more indicates over-instrumentation
- **< 20 spans under 5ms** — very short spans add noise
- **No orphan spans** — every span except root must have a parent
- **Root spans cannot be SpanKindClient/SpanKindProducer**
- **Error spans must have a description** — `span.SetStatus(codes.Error, "description required")`

---

## Span Budget

| Instrument | Recommended |
|---|---|
| Incoming HTTP request | ✅ Always |
| Outgoing HTTP/gRPC call | ✅ Always |
| DB query | ✅ Always |
| External service call | ✅ Always |
| Internal helper function | ❌ Skip unless genuinely slow or failure-prone |
| Utility called thousands of times per second | ❌ Creates noise and cardinality |

**Rule:** Inbound handler + outbound calls + one business span = ≤ 6 spans total. Never span every helper function — trace the boundary, not the implementation.

Anti-pattern: instrumenting every method in a hot path. Instrument boundaries (network calls, DB, queue) and the entry-point handler.

---

## Workflow Boundaries

**Same user operation across services → continue the trace** (propagate W3C traceparent)

```go
// Outgoing HTTP: inject W3C traceparent into request headers
otel.GetTextMapPropagator().Inject(ctx, propagation.HeaderCarrier(req.Header))
```

**Separate jobs / separate queue deliveries / separate batch runs → new root span**

```go
// Start a new independent trace for a background job
ctx, span := tracer.Start(context.Background(), "nightly-cleanup",
    trace.WithSpanKind(trace.SpanKindServer),
)
defer span.End()
```

**Related but not parent-child (e.g. queue consumer) → use `trace.Link`**

```go
// Consumer span: new root trace with a Link back to producer
ctx, span := tracer.Start(context.Background(), "process invoice.created",
    trace.WithSpanKind(trace.SpanKindConsumer),
    trace.WithLinks(trace.Link{SpanContext: producerSpanCtx}),
)
defer span.End()
```

See `references/async-messaging.md` for full Kafka/SQS/RabbitMQ link patterns.
