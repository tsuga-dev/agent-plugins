# Span Naming, Kind, and Status Rules — C++

> **Last verified:** 2026-03-23 | SDK: `opentelemetry-cpp` 1.26.0
>
> See also: `otel-semantic-conventions` skill for attribute naming; `references/otel-reference.md` for instrument types.

## Span Naming

**Pattern:** `{verb} {object}` in sentence case. Low-cardinality — no IDs, no raw paths.

| BAD | GOOD | Why |
|-----|------|-----|
| `"GET /users/" + userId + "/orders"` | `GET /users/{id}/orders` | String concatenation with ID → unbounded cardinality |
| `processOrder` | `process order` | Space-separated verb-object |
| `dbQuery` | `SELECT orders` | Include operation and object |

```cpp
// BAD
auto span = tracer->StartSpan("GET /users/" + user_id + "/orders");

// GOOD
auto span = tracer->StartSpan("GET /users/{id}/orders");
span->SetAttribute("user.id", user_id);
```

## Span Kind Decision Tree

| Scenario | SpanKind |
|----------|----------|
| Inbound HTTP/gRPC handler | `opentelemetry::trace::SpanKind::kServer` |
| Outbound HTTP, gRPC, DB call | `opentelemetry::trace::SpanKind::kClient` |
| Publishing to Kafka/SQS/AMQP | `opentelemetry::trace::SpanKind::kProducer` |
| Consuming from queue | `opentelemetry::trace::SpanKind::kConsumer` |
| Local logic (no I/O) | `opentelemetry::trace::SpanKind::kInternal` |

```cpp
// Inbound
opentelemetry::trace::StartSpanOptions opts;
opts.kind = opentelemetry::trace::SpanKind::kServer;
auto span = tracer->StartSpan("POST /orders", {}, opts);

// Outbound
opentelemetry::trace::StartSpanOptions client_opts;
client_opts.kind = opentelemetry::trace::SpanKind::kClient;
auto span = tracer->StartSpan("GET products-service", {}, client_opts);
```

## HTTP Status → Span Status Mapping

| Span Kind | HTTP 4xx | HTTP 5xx |
|-----------|----------|----------|
| kServer | **kUnset** (client's error, not server's) | kError |
| kClient | **kError** (the call failed) | kError |

```cpp
// Server span: 400 is NOT an error
if (status_code >= 500) {
    span->SetStatus(opentelemetry::trace::StatusCode::kError, "Internal server error");
}
// 4xx on server: leave as default kUnset

// Client span: 4xx IS an error
if (status_code >= 400) {
    span->SetStatus(opentelemetry::trace::StatusCode::kError,
                   "HTTP " + std::to_string(status_code));
}
```

## Headless Operations Pattern

```cpp
// BAD: background thread creates child spans with no parent — orphan spans
std::thread([]() {
    auto span = tracer->StartSpan("query-stale-records");  // Orphan!
}).detach();

// GOOD: create SERVER root span wrapping the entire task
opentelemetry::trace::StartSpanOptions root_opts;
root_opts.kind = opentelemetry::trace::SpanKind::kServer;
auto root_span = tracer->StartSpan("nightly-cleanup",
    {
        {"task.name",    "nightly-cleanup"},
        {"task.trigger", "cron"},
    },
    root_opts
);
auto root_scope = tracer->WithActiveSpan(root_span);

// Child spans inherit root as parent via thread context
auto child_span  = tracer->StartSpan("query-stale-records");
auto child_scope = tracer->WithActiveSpan(child_span);
// ... work ...
child_span->End();
root_span->End();
```

## Span Hygiene Rules

- **< 10 INTERNAL spans per trace** — more indicates over-instrumentation
- **< 20 spans under 5ms** — C++ has no auto-instrumentation; be deliberate about what you instrument
- **No orphan spans** — every span except root must have a parent
- **Root spans cannot be kClient or kProducer**
- **Error spans must include a description** — `span->SetStatus(StatusCode::kError, "description")`

## Span Budget

| Signal | Per-request budget | Notes |
|--------|-------------------|-------|
| Incoming HTTP/gRPC request | 1 span | Always instrument; root span for the trace |
| Outgoing HTTP/gRPC call | 1 span per call | Always instrument; kClient kind |
| DB query | 1 span per query | Always instrument |
| External service call | 1 span per call | Always instrument |
| Business transaction (e.g., `process order`) | 1 span | Instrument key domain operations |
| Internal helper function | Skip unless measurably slow | No auto-instrumentation to fall back on; be selective |
| Utility called thousands of times per request | Skip | Creates noise; use metric instead |
| Loop iteration (per-item span in a batch) | Only if needed | Confirm sampling is in place first |

Anti-pattern: instrumenting every function. The goal is minimum spans needed to diagnose failures and measure latency at service boundaries.

## Workflow Boundaries

**Rule:** Same user operation across services → continue the trace (propagate W3C `traceparent`). Separate operations, separate queue deliveries, or separate background jobs → new root span.

Never propagate a parent context from one unrelated job into another.

### Continue the trace (outbound HTTP call)

```cpp
// Inject current context into outbound HTTP headers
httplib::Headers headers;
HttplibMutableCarrier carrier(headers);
opentelemetry::context::propagation::GlobalTextMapPropagator::GetGlobalPropagator()
    ->Inject(carrier, opentelemetry::context::RuntimeContext::GetCurrent());

httplib::Client cli("downstream-service");
auto result = cli.Get("/api/resource", headers);
```

### New root span (background job / scheduled task)

```cpp
// setNoParent equivalent: do NOT set opts.parent; leave empty (default = new root
// when no active span is present in the current thread context)
opentelemetry::trace::StartSpanOptions opts;
opts.kind = opentelemetry::trace::SpanKind::kServer;
auto root_span = tracer->StartSpan("nightly-cleanup",
    {{"task.trigger", "cron"}}, opts);
auto scope = tracer->WithActiveSpan(root_span);
doWork();
root_span->End();
```

### Related but not parent-child (async / queue)

```cpp
// Extract producer context, then create a new root span with a Link
// (consumer is independent — same origin, different lifecycle)
auto producer_span_ctx = opentelemetry::trace::GetSpan(extracted_context)->GetContext();

opentelemetry::trace::StartSpanOptions opts;
opts.kind = opentelemetry::trace::SpanKind::kConsumer;
// opts.parent NOT set — this is a new root
auto span = tracer->StartSpan(
    "process order",
    {
        {"messaging.producer.trace_id", TraceIdToHex(producer_span_ctx.trace_id())},
        {"messaging.producer.span_id",  SpanIdToHex(producer_span_ctx.span_id())},
    },
    opts
);
```

> **→** `references/async-messaging.md` — full Kafka, AMQP, SQS patterns with semconv and MapCarrier.
