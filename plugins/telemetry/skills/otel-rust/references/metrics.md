# Metrics — Rust OTel

> Last verified: 2026-03-23 | SDK: opentelemetry 0.31.0 / opentelemetry-otlp 0.31.0

## Instrument Selection

| Question | Answer | Instrument |
|----------|--------|------------|
| Counts events that only go up? | Yes | **Counter** |
| Counts things that go up and down? | Yes | **UpDownCounter** |
| Measures distribution (latency, size)? | Yes | **Histogram** |
| Measures a current spot value synchronously (call `.record()` on each measurement)? | Yes | **Synchronous Gauge** |
| Measures a current spot value via callback at collection time? | Yes | **Observable Gauge** |
| Tracks a cumulative total sampled at collection? | Yes | **Observable Counter** |
| Tracks fluctuating total sampled at collection? | Yes | **Observable UpDownCounter** |

> Unsure between metric / span / log? → `signal-choice-advisor`

## MeterProvider Setup

Metrics require an explicit `SdkMeterProvider` with a `PeriodicReader`. Without this, all metric calls are no-ops.

```rust
use opentelemetry::global;
use opentelemetry_sdk::metrics::{PeriodicReader, SdkMeterProvider};

// GOOD — MeterProvider with reader attached
let metric_exporter = opentelemetry_otlp::MetricExporter::builder()
    .with_http()
    .build()?;
let metric_reader = PeriodicReader::builder(metric_exporter).build();
let meter_provider = SdkMeterProvider::builder()
    .with_reader(metric_reader)
    .with_resource(resource)
    .build();
global::set_meter_provider(meter_provider);

// BAD — no reader; metrics are never exported
// let meter_provider = SdkMeterProvider::builder().build();
// global::set_meter_provider(meter_provider);
```

## All Instruments with Rust API

### Counter

```rust
use opentelemetry::{global, KeyValue};

let meter = global::meter("my-service");

// GOOD — counter with description, unit, and low-cardinality attributes
let request_counter = meter
    .u64_counter("http.server.request.count")
    .with_description("Total number of HTTP server requests processed")
    .with_unit("{request}")
    .build();

request_counter.add(1, &[
    KeyValue::new("http.request.method", "GET"),
    KeyValue::new("http.response.status_code", 200_i64),
]);

// Float variant
let bytes_counter = meter
    .f64_counter("network.bytes.sent")
    .with_unit("By")
    .build();
bytes_counter.add(1024.0, &[KeyValue::new("direction", "outbound")]);
```

### UpDownCounter

```rust
// GOOD — tracks connections that go up and down
let active_connections = meter
    .i64_up_down_counter("db.client.connections.usage")
    .with_description("Number of active database connections")
    .with_unit("{connection}")
    .build();

active_connections.add(1, &[KeyValue::new("pool.name", "primary")]);   // acquired
active_connections.add(-1, &[KeyValue::new("pool.name", "primary")]);  // released
```

### Histogram

```rust
// GOOD — histogram for request duration with route attribute
let request_duration = meter
    .f64_histogram("http.server.request.duration")
    .with_description("Duration of HTTP server requests")
    .with_unit("ms")
    .build();

request_duration.record(42.5, &[
    KeyValue::new("http.route", "/api/v1/users"),
    KeyValue::new("http.request.method", "GET"),
]);

// Integer variant (for byte sizes)
let body_size = meter
    .u64_histogram("http.server.request.body.size")
    .with_unit("By")
    .build();
```

### Synchronous Gauge

Use when you need to record a value imperatively at a specific point in time (e.g., per-request thread count, cache hit ratio per request).

```rust
// GOOD — synchronous gauge: call .record() when the value changes
let cache_hit_ratio = meter
    .f64_gauge("cache.hit.ratio")
    .with_description("Current cache hit ratio for the request")
    .with_unit("1")
    .build();

cache_hit_ratio.record(0.87, &[KeyValue::new("cache.name", "session")]);
```

> Synchronous Gauge is available in `opentelemetry` 0.27.x via `meter.f64_gauge(...)` / `meter.u64_gauge(...)`.

### Observable Gauge

Use when the value is best read on-demand from an in-memory source (CPU utilization, queue depth, heap usage, etc.).

```rust
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

let queue_depth = Arc::new(AtomicU64::new(0));
let queue_depth_for_callback = queue_depth.clone();

// GOOD — observable gauge: callback reads pre-computed in-memory value
let _gauge = meter
    .u64_observable_gauge("messaging.queue.depth")
    .with_description("Current message queue depth")
    .with_unit("{message}")
    .with_callback(move |observer| {
        observer.observe(
            queue_depth_for_callback.load(Ordering::Relaxed),
            &[KeyValue::new("queue", "orders")],
        );
    })
    .build();
```

> **Observable callback rule:** The callback is invoked by `PeriodicReader` on every export interval (default: 60 s). Do NOT perform blocking I/O or expensive computation inside it. Read from an `AtomicU64`, `Arc<Mutex<T>>`, or similar in-memory value.

### Observable Counter

```rust
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

let total_bytes_read = Arc::new(AtomicU64::new(0));
let bytes_for_callback = total_bytes_read.clone();

let _counter = meter
    .u64_observable_counter("io.bytes.read")
    .with_unit("By")
    .with_callback(move |observer| {
        observer.observe(bytes_for_callback.load(Ordering::Relaxed), &[]);
    })
    .build();
```

### Observable UpDownCounter

```rust
let _updown = meter
    .i64_observable_up_down_counter("thread.pool.active")
    .with_unit("{thread}")
    .with_callback(|observer| {
        observer.observe(get_active_thread_count() as i64, &[]);
    })
    .build();
```

## Cardinality Warning

```rust
// BAD — user_id has unbounded cardinality; creates millions of metric series
request_counter.add(1, &[
    KeyValue::new("user.id", user_id.to_string()),  // NEVER do this
]);

// GOOD — low-cardinality attributes only
request_counter.add(1, &[
    KeyValue::new("http.request.method", "GET"),
    KeyValue::new("user.tier", "premium"),          // bounded set
]);
```

**Rules:**
- Never use `user_id`, `request_id`, `trace_id`, email, or any per-request value as a metric attribute
- Maximum ~100 unique values per attribute key
- Each unique attribute combination is a separate series in the collector backend

## Naming Rules

- Dot notation: `http.server.request.duration` not `http_server_request_duration`
- No service name in metric name: `web_backend_latency` → BAD
- No units in metric name: `latency_ms` → BAD; set `.with_unit("ms")` instead
- No environment in metric name: `prod_request_count` → BAD
- Check `otel-semantic-conventions` before inventing custom names

## Cross-Skill Pointers

| Topic | Skill |
|-------|-------|
| Metric vs span vs log decision | `signal-choice-advisor` |
| Attribute key naming | `otel-semantic-conventions` |
| All instrument types reference table | `references/otel-reference.md` |
| Cardinality / naming audit | `tsuga-audit-metrics` |
