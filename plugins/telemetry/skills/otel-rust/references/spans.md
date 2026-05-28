# Span Naming, Kind, and Status Rules — Rust

> Last verified: 2026-03-23 | SDK: opentelemetry 0.31.0 / tracing-opentelemetry 0.32.1
>
> See also: `otel-semantic-conventions` skill for attribute naming; `references/otel-reference.md` for instrument types.

## Span Naming

**Pattern:** `{verb} {object}` in sentence case. Low-cardinality — no IDs, no raw paths.

| BAD | GOOD | Why |
|-----|------|-----|
| `format!("GET /users/{}/orders", user_id)` | `GET /users/{id}/orders` | Format strings create unbounded cardinality |
| `processOrder` | `process order` | Space-separated verb-object |
| `dbQuery` | `SELECT orders` | Include operation and object |

```rust
// BAD
#[tracing::instrument]
async fn get_user_orders(user_id: u64) { ... }
// span name becomes "get_user_orders" — camelCase and no verb-object pattern

// GOOD — explicit name via name parameter
#[tracing::instrument(name = "GET /users/{id}/orders", fields(user.id = user_id))]
async fn get_user_orders(user_id: u64) { ... }
```

## `#[tracing::instrument]` — Recommended Span Creation

`#[tracing::instrument]` is the idiomatic Rust way to create spans. It automatically:
- Creates a span with the function name (override with `name = "..."`)
- Captures function arguments as span fields (skip sensitive ones with `skip(...)`)
- Handles async context propagation correctly — avoids the `span.enter()` pitfall

```rust
use tracing::instrument;

// GOOD — idiomatic span per async function
#[instrument(
    name = "process order",
    fields(order.id = %order_id, user.id = %user_id)
)]
async fn process_order(order_id: u64, user_id: u64) -> Result<(), MyError> {
    tracing::info!("processing order");
    do_work().await?;
    Ok(())
}

// GOOD — skip large or sensitive parameters
#[instrument(skip(db_pool, password), fields(user.email = %email))]
async fn authenticate(db_pool: &Pool, email: &str, password: &str) -> Result<User, Error> {
    ...
}
```

For sub-block spans within a function, use `info_span!` with `.instrument()`:

```rust
use tracing::Instrument;

async fn handle_batch(items: Vec<Item>) {
    for item in items {
        async {
            process_item(&item).await;
        }
        .instrument(tracing::info_span!("process item", item.id = item.id))
        .await;
    }
}
```

## Span Kind Decision Tree

| Scenario | Kind |
|----------|------|
| Inbound HTTP/gRPC handler | `SERVER` |
| Outbound HTTP, gRPC, DB call | `CLIENT` |
| Publishing to Kafka/SQS/RabbitMQ | `PRODUCER` |
| Consuming from queue | `CONSUMER` |
| Local method (no I/O) | `INTERNAL` |

```rust
use opentelemetry::trace::SpanKind;

// With tracing macro — set kind via otel.kind field
#[tracing::instrument(fields(otel.kind = "server"))]
async fn handle_request() { ... }

// With raw OTel tracer — direct kind setting
let span = tracer
    .span_builder("POST /orders")
    .with_kind(SpanKind::Server)
    .start(&tracer);
```

## HTTP Status → Span Status Mapping

| Span Kind | HTTP 4xx | HTTP 5xx |
|-----------|----------|----------|
| SERVER | **UNSET** (server did its job) | ERROR |
| CLIENT | **ERROR** (call failed) | ERROR |

```rust
use opentelemetry::trace::{Status, Span};

// Server span: 400 is NOT an error
if status_code >= 500 {
    span.set_status(Status::error("Internal server error"));
}
// 4xx on server: leave as default UNSET

// Client span: 4xx IS an error
if status_code >= 400 {
    span.set_status(Status::error(format!("HTTP {}", status_code)));
}
```

## Headless Operations Pattern

```rust
use opentelemetry::trace::SpanKind;

// BAD: tokio task with no parent context → orphaned spans
tokio::spawn(async {
    let span = tracer.start("query-stale-records");  // Orphan — no parent
});

// GOOD: create root span, propagate context into task via .instrument()
use tracing::Instrument;

let root_span = tracing::info_span!(
    "nightly-cleanup",
    otel.kind = "server",
    task.name = "nightly-cleanup",
    task.trigger = "cron",
);

async {
    // child spans here have nightly-cleanup as parent
    let _child = tracing::info_span!("query-stale-records").entered();
    query_stale_records().await;
}
.instrument(root_span)
.await;
```

## Span Hygiene Rules

- **< 10 INTERNAL spans per trace** — more indicates over-instrumentation
- **< 20 spans under 5ms** — short spans add noise
- **No orphan spans** — every span except root must have a parent
- **Root spans cannot be CLIENT or PRODUCER**
- **Error spans must include a description** — `Status::error("description")`

## Span Budget

| Signal | Per-request budget | Notes |
|--------|--------------------|-------|
| Incoming HTTP request | 1 (always) | Use `#[instrument]` or Axum middleware |
| Outgoing HTTP / gRPC call | 1 per call (always) | Manual inject via `opentelemetry-http` |
| DB query | 1 per query (always) | Manual; no auto-instrumentation in Rust |
| External service call | 1 per call (always) | — |
| Business transaction (order.place, payment.charge) | 1 per operation (yes) | Use `#[instrument]` |
| Internal helper function | 0 (skip) | Unless measurably slow or failure-prone |
| Utility called thousands of times per request | 0 (skip) | Creates noise; use metric instead |
| Loop iteration (per-item span in a batch) | Use only if sampling is confirmed | Confirm sampling in place first |

Anti-pattern: instrumenting every function with `#[instrument]`. The span budget goal is minimum spans needed to diagnose failures and measure latency at service boundaries.

## Workflow Boundaries

**Rule:** Same user operation across services → continue the trace (propagate W3C `traceparent`). Separate operations, separate queue deliveries, or separate scheduled jobs → new root span.

Never propagate a parent context from one unrelated job into another.

### Continue the trace (outbound HTTP call)

```rust
use opentelemetry::global;
use opentelemetry_http::HeaderInjector;
use tracing_opentelemetry::OpenTelemetrySpanExt;

// GOOD — inject current span context into outbound request headers
let cx = tracing::Span::current().context();
let mut headers = reqwest::header::HeaderMap::new();
global::get_text_map_propagator(|propagator| {
    propagator.inject_context(&cx, &mut HeaderInjector(&mut headers));
});
let response = client.get(url).headers(headers).send().await?;
```

### New root span (scheduled job or batch)

```rust
// GOOD — setNoParent equivalent: span created outside any parent context
// Just create the span without an active parent context
let root_span = tracing::info_span!(
    "nightly-cleanup",
    otel.kind = "server",
    task.name = "nightly-cleanup",
    task.trigger = "cron",
);

async { do_work().await }.instrument(root_span).await;
```

### Related but not parent-child (async / queue)

```rust
// GOOD — add_link() connects traces for navigation without parent-child
let span = tracing::info_span!("process order");
{
    use tracing_opentelemetry::OpenTelemetrySpanExt;
    if producer_span_ctx.is_valid() {
        span.add_link(producer_span_ctx);  // link to producer trace
    }
}
async { process().await }.instrument(span).await;
```

> **→** `references/async-messaging.md` — full Kafka, AMQP, SQS patterns with semconv.
> **→** `references/propagation.md` — HTTP extract/inject patterns for Axum, reqwest, tonic.
