# Metrics — Go OTel SDK

> **Last verified:** 2026-03-23 | SDK: `go.opentelemetry.io/otel/metric` v1.42.0

This file covers all metric instrument types, the Go API, async instruments, and cardinality rules. For SDK initialization see `references/quickstart.md`. For naming and unit rules see `references/otel-reference.md`.

---

## Instrument Selection

| Question | Answer | Use |
|---|---|---|
| Counts discrete events (requests, errors)? | Value only increases | **Counter** |
| Current value that goes up and down (queue depth, connections)? | Value fluctuates | **UpDownCounter** |
| Distribution of values (latency, payload size)? | You need p50/p95/p99 | **Histogram** |
| Spot measurement you have right now in code (cache hit ratio, temperature)? | Value available at call time | **Gauge** (synchronous) |
| Total you read from a system counter (bytes sent, GC count)? | Polled periodically | **Observable Counter** |
| Current total polled from runtime (heap size, thread count)? | Polled periodically | **Observable UpDownCounter** |
| Spot measurement polled periodically (CPU %, disk utilization)? | Only known at collection time | **Observable Gauge** |

> Still unsure whether this measurement should be a metric, a span attribute, or a log field? → `signal-choice-advisor`

---

## Synchronous Instruments

### Counter

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/attribute"
    "go.opentelemetry.io/otel/metric"
)

meter := otel.Meter("my-service")

requestCounter, err := meter.Int64Counter("http.server.request.count",
    metric.WithUnit("{request}"),
    metric.WithDescription("Total HTTP requests received"),
)
if err != nil {
    // handle instrument creation error
}

requestCounter.Add(ctx, 1, metric.WithAttributes(
    attribute.String("http.request.method", "GET"),
    attribute.Int("http.response.status_code", 200),
))
```

Float64 variant: `meter.Float64Counter(name, ...)` — same API, use for decimal increments.

### UpDownCounter

```go
queueDepth, _ := meter.Int64UpDownCounter("messaging.client.consumed.messages",
    metric.WithUnit("{message}"),
    metric.WithDescription("Messages currently in processing queue"),
)

// Enqueue: increment
queueDepth.Add(ctx, 1, metric.WithAttributes(attribute.String("queue", "jobs")))

// Dequeue: decrement
queueDepth.Add(ctx, -1, metric.WithAttributes(attribute.String("queue", "jobs")))
```

### Histogram

```go
latency, _ := meter.Float64Histogram("http.server.request.duration",
    metric.WithUnit("ms"),
    metric.WithDescription("HTTP request duration in milliseconds"),
    // Optional: override default boundaries
    metric.WithExplicitBucketBoundaries(0, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000),
)

latency.Record(ctx, elapsed.Milliseconds(), metric.WithAttributes(
    attribute.String("http.request.method", "GET"),
    attribute.String("http.route", "/api/v1/orders/{id}"),
))
```

### Gauge (synchronous) — stable since SDK v1.23

Use when you have the measurement value at the call site (not polling).

```go
// GOOD: you know the temperature right now; record it inline
cacheHitRatio, _ := meter.Float64Gauge("cache.hit.ratio",
    metric.WithUnit("1"),
    metric.WithDescription("Fraction of cache lookups that hit"),
)

// Record a spot measurement wherever you compute the value
cacheHitRatio.Record(ctx, hits/float64(hits+misses), metric.WithAttributes(
    attribute.String("cache.name", "session-cache"),
))
```

```go
// Int64 variant
connectionCount, _ := meter.Int64Gauge("db.client.connections.idle",
    metric.WithUnit("{connection}"),
)
connectionCount.Record(ctx, int64(pool.IdleCount()))
```

**Gauge vs Observable Gauge:**
- **Gauge (sync):** you have the value right now in your code path → call `Record()` directly
- **Observable Gauge (async):** value is only knowable by querying a system at export time → use `RegisterCallback`

---

## Asynchronous (Observable) Instruments

Use async instruments when the value is polled at collection time, not available inline.

### Single instrument with callback

```go
_, err = meter.Float64ObservableGauge("process.memory.heap",
    metric.WithUnit("By"),
    metric.WithDescription("Current heap memory usage"),
    metric.WithFloat64Callback(func(_ context.Context, o metric.Float64Observer) error {
        o.Observe(float64(runtime.MemStats{}.HeapAlloc))
        return nil
    }),
)
```

> **Callback rules:** The callback is called by `PeriodicReader` on each export cycle. Do NOT block, make network calls, or acquire locks inside it.

### Multiple instruments in one callback (recommended for batching)

Use `RegisterCallback` to share one callback across multiple instruments — more efficient than separate callbacks per instrument.

```go
heapAlloc, _ := meter.Float64ObservableGauge("process.memory.heap", metric.WithUnit("By"))
heapIdle, _ := meter.Float64ObservableGauge("process.memory.heap.idle", metric.WithUnit("By"))
gcCount, _ := meter.Int64ObservableCounter("process.runtime.go.gc.count")

_, err = meter.RegisterCallback(
    func(_ context.Context, o metric.Observer) error {
        var m runtime.MemStats
        runtime.ReadMemStats(&m)
        o.ObserveFloat64(heapAlloc, float64(m.HeapAlloc))
        o.ObserveFloat64(heapIdle, float64(m.HeapIdle))
        o.ObserveInt64(gcCount, int64(m.NumGC))
        return nil
    },
    heapAlloc, heapIdle, gcCount,
)
```

### Observable Counter and UpDownCounter

```go
// Observable Counter — monotonically increasing total (e.g. bytes sent)
_, _ = meter.Float64ObservableCounter("network.bytes.sent",
    metric.WithUnit("By"),
    metric.WithFloat64Callback(func(_ context.Context, o metric.Float64Observer) error {
        o.Observe(getTotalBytesSent())
        return nil
    }),
)

// Observable UpDownCounter — fluctuating total (e.g. goroutine count)
_, _ = meter.Int64ObservableUpDownCounter("process.runtime.go.goroutines",
    metric.WithInt64Callback(func(_ context.Context, o metric.Int64Observer) error {
        o.Observe(int64(runtime.NumGoroutine()))
        return nil
    }),
)
```

---

## Cardinality Warning

```go
// BAD — user ID has unbounded cardinality; creates millions of time series
requestCounter.Add(ctx, 1, metric.WithAttributes(
    attribute.String("user.id", userID),          // never in metric attributes
    attribute.String("request.id", requestID),    // never in metric attributes
))

// GOOD — low-cardinality dimensions only
requestCounter.Add(ctx, 1, metric.WithAttributes(
    attribute.String("http.request.method", "GET"),
    attribute.Int("http.response.status_code", 200),
))
```

Rule: Metric attributes must have bounded, low cardinality (tens to hundreds of distinct values, not thousands). User IDs, request IDs, URLs with path params, trace IDs → never in metric attributes.

---

## Histogram Boundary Configuration

Default OTel histogram boundaries are `[0, 5, 10, 25, 50, 75, 100, 250, 500, 750, 1000, 2500, 5000, 7500, 10000]` milliseconds. Override when your latency profile needs different resolution:

```go
latency, _ := meter.Float64Histogram("db.client.operation.duration",
    metric.WithUnit("ms"),
    metric.WithExplicitBucketBoundaries(0, 1, 5, 10, 25, 50, 100, 250, 500, 1000),
)
```

Override at the `MeterProvider` level to apply globally:

```go
sdkmetric.NewMeterProvider(
    sdkmetric.WithView(
        sdkmetric.NewView(
            sdkmetric.Instrument{Name: "http.server.request.duration"},
            sdkmetric.Stream{Aggregation: sdkmetric.AggregationExplicitBucketHistogram{
                Boundaries: []float64{0, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000},
            }},
        ),
    ),
    // ... other options
)
```

---

## Naming Quick Check

Before finalizing any metric name, verify it against these rules (full rules in `references/otel-reference.md`):

| BAD | GOOD | Rule |
|---|---|---|
| `request_count` | `http.server.request.count` | Use dot notation; use semconv name |
| `myservice.requests` | `http.server.request.count` | No service name prefix |
| `latency_ms` | `http.server.request.duration` + `unit="ms"` | No units in name |
| `prod_errors` | `http.server.request.count` + resource attr | No env prefix |

> Check `otel-semantic-conventions` before inventing custom metric names.
