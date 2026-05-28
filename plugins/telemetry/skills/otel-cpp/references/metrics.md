# Metrics — C++ OTel

> **Last verified:** 2026-03-23 | SDK: `opentelemetry-cpp` 1.26.0

## Instrument Selection

| Question | Answer | Instrument |
|----------|--------|------------|
| Counts events that only go up? | Yes | **Counter** |
| Counts things that go up and down? | Yes | **UpDownCounter** |
| Measures distribution (latency, size)? | Yes | **Histogram** |
| Measures a current spot value synchronously (call `Record()` on each measurement)? | Yes | **Synchronous Gauge** |
| Measures a current spot value via callback at collection time? | Yes | **Observable Gauge** |
| Tracks a cumulative total sampled at collection? | Yes | **Observable Counter** |
| Tracks fluctuating total sampled at collection? | Yes | **Observable UpDownCounter** |

> Unsure between metric / span / log? → `signal-choice-advisor`

## Getting a Meter

```cpp
#include "opentelemetry/metrics/provider.h"

namespace metrics_api = opentelemetry::metrics;

// Always use the global provider; do not cache the meter across translation units
auto meter = metrics_api::Provider::GetMeterProvider()->GetMeter("my-app", "1.0.0");
```

## All Instruments with C++ API

### Counter

Monotonically increasing. Use for events that only go up (requests, errors, bytes sent).

```cpp
// GOOD — counter with low-cardinality attributes
auto request_counter = meter->CreateUInt64Counter(
    "http.server.request.count",
    "Total number of HTTP server requests",
    "{request}"
);
request_counter->Add(1, {
    {"http.request.method",      "GET"},
    {"http.response.status_code", static_cast<int64_t>(200)}
});

// BAD — user_id has unbounded cardinality; creates millions of series
request_counter->Add(1, {{"user.id", user_id}});   // NEVER do this
```

Double variant: `meter->CreateDoubleCounter(...)`.

### UpDownCounter

Supports positive and negative deltas. Use for fluctuating counts (active connections, queue depth).

```cpp
// GOOD
auto active_conns = meter->CreateInt64UpDownCounter(
    "db.client.connections.usage",
    "Number of active database connections",
    "{connection}"
);
active_conns->Add(1,  {{"pool.name", "primary"}});   // acquired
active_conns->Add(-1, {{"pool.name", "primary"}});   // released
```

### Histogram

Measures distributions of values. Use for latency, request body size, processing time.

```cpp
// GOOD
auto request_duration = meter->CreateDoubleHistogram(
    "http.server.request.duration",
    "Duration of HTTP server requests",
    "ms"
);
request_duration->Record(42.5, {
    {"http.route", "/api/v1/users"}
});

// Integer variant for byte sizes
auto body_size = meter->CreateUInt64Histogram(
    "http.server.request.body.size",
    "Size of HTTP request bodies",
    "By"
);
```

### Synchronous Gauge

Records a spot value imperatively (call `Record()` when the value changes). Added in `opentelemetry-cpp` v1.18.0.

```cpp
// GOOD — synchronous gauge: call Record() on each measurement
auto cache_hit_ratio = meter->CreateDoubleGauge(
    "cache.hit.ratio",
    "Current cache hit ratio",
    "1"
);
// Call Record() whenever the value changes — not on a callback
cache_hit_ratio->Record(0.87, {{"cache.name", "session"}});

// BAD — use Observable Gauge instead if the value is read from an in-memory source
// at collection time, not pushed per-request
```

### Observable Gauge

Value is read via callback at each collection interval. Use for values best read on-demand (CPU utilization, memory usage, queue depth sampled from system).

```cpp
// GOOD — observable gauge: callback reads current in-memory value
auto cpu_gauge = meter->CreateDoubleObservableGauge(
    "system.cpu.utilization",
    "CPU utilization",
    "1"
);
cpu_gauge->AddCallback(
    [](opentelemetry::metrics::ObserverResult result, void*) {
        // Keep this fast — called on every export interval (default: 60s)
        // Do NOT do blocking I/O here
        result.Observe(GetCpuUtilization(), {{"cpu.core", "0"}});
    },
    nullptr
);
```

> Observable callback rule: the callback runs on the SDK's periodic export thread. Do NOT perform blocking I/O, take locks held by application threads, or do expensive computation. Read from pre-computed `std::atomic` or similar in-memory values.

### Observable Counter

Monotonically increasing total, sampled at collection. Use for byte counters or event totals read from system state.

```cpp
// GOOD — observable counter reads a monotonically increasing atomic
std::atomic<uint64_t> total_bytes_sent{0};

auto bytes_counter = meter->CreateUInt64ObservableCounter(
    "io.bytes.sent",
    "Total bytes sent",
    "By"
);
bytes_counter->AddCallback(
    [](opentelemetry::metrics::ObserverResult result, void* state) {
        auto* counter = static_cast<std::atomic<uint64_t>*>(state);
        result.Observe(counter->load(), {});
    },
    &total_bytes_sent
);
```

### Observable UpDownCounter

Fluctuating total sampled at collection. Use for thread pool active count, live connection count read from system state.

```cpp
auto thread_gauge = meter->CreateInt64ObservableUpDownCounter(
    "thread.pool.active",
    "Number of active threads in pool",
    "{thread}"
);
thread_gauge->AddCallback(
    [](opentelemetry::metrics::ObserverResult result, void* state) {
        auto* pool = static_cast<ThreadPool*>(state);
        result.Observe(static_cast<int64_t>(pool->active_count()), {});
    },
    &my_thread_pool
);
```

## Cardinality Warning

```cpp
// BAD — userId has unbounded cardinality; creates millions of time series
request_counter->Add(1, {
    {"user.id", user_id}   // NEVER use per-request identifiers as metric attributes
});

// GOOD — low-cardinality attributes only
request_counter->Add(1, {
    {"http.request.method",       "GET"},
    {"http.response.status_code", static_cast<int64_t>(200)},
    {"user.tier",                 "premium"}   // bounded set of values
});
```

Rules:
- Never use `userId`, `requestId`, `traceId`, email, IP address, or any per-request value as a metric attribute
- Target fewer than ~100 unique values per attribute key across all label combinations
- Each unique attribute combination is a separate time series in the collector backend

## Naming Rules

- Dot notation: `http.server.request.duration` not `http_server_request_duration`
- No service name in metric name: `web_backend_latency` is BAD
- No units in metric name: `latency_ms` is BAD; set the `unit` parameter instead
- No environment or version in metric name: `prod_errors`, `v2_latency` are BAD
- Check `otel-semantic-conventions` before inventing custom names

## C++ Attribute Type Notes

C++ uses `opentelemetry::common::AttributeValue`, which is a variant type. Prefer explicit casts:

```cpp
// GOOD — explicit types
span->SetAttribute("count",    static_cast<int64_t>(42));
span->SetAttribute("ratio",    0.95);           // double — OK
span->SetAttribute("endpoint", "/api/orders");  // const char* → string_view — OK

// BAD — implicit int conversion may not produce int64_t on all platforms
span->SetAttribute("count", 42);
```

## Cross-Skill Pointers

| Topic | Skill |
|-------|-------|
| Metric vs span vs log decision | `signal-choice-advisor` |
| Attribute key naming | `otel-semantic-conventions` |
| All instrument types table | `references/otel-reference.md` |
| Cardinality / naming audit | `tsuga-audit-metrics` |
