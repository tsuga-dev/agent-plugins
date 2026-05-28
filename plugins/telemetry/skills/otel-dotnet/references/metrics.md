# Metrics — .NET OTel

> **Last verified:** 2026-03-23 | SDK: OpenTelemetry NuGet 1.15.x / .NET 8+

## Instrument Selection

| Question | Answer | Instrument |
|----------|--------|------------|
| Counts events that only go up? | Yes | **Counter** |
| Counts things that go up and down? | Yes | **UpDownCounter** |
| Measures distribution (latency, size)? | Yes | **Histogram** |
| Measures a current spot value synchronously (call `.Record()` on each measurement)? | Yes | **Synchronous Gauge** |
| Measures a current spot value via callback at collection time? | Yes | **Observable Gauge** |
| Tracks a cumulative total sampled at collection? | Yes | **Observable Counter** |
| Tracks fluctuating total sampled at collection? | Yes | **Observable UpDownCounter** |

> Unsure between metric / span / log? → `signal-choice-advisor`

## Native Meter API vs OTel Metrics API

Prefer `System.Diagnostics.Metrics.Meter` (native .NET) with the OTel SDK observing it. The OTel SDK hooks into the native Meter infrastructure when you call `.AddMeter("name")` in `.WithMetrics()`.

```csharp
// GOOD — native Meter; OTel SDK observes it via .AddMeter("my-service")
using System.Diagnostics.Metrics;
private static readonly Meter _meter = new Meter("my-service", "1.0.0");

// Registration in Program.cs:
builder.Services.AddOpenTelemetry()
    .WithMetrics(metrics => metrics
        .AddMeter("my-service")   // REQUIRED — must match Meter constructor name
        .AddOtlpExporter()
    );
```

The `Meter` name passed to `new Meter(...)` must exactly match the name in `.AddMeter(...)`. Case-sensitive.

## All Instruments with C# API

### Counter

```csharp
using System.Diagnostics.Metrics;

private static readonly Meter _meter = new Meter("my-service", "1.0.0");

var requestCounter = _meter.CreateCounter<long>(
    "http.server.request.count",
    unit: "{request}",
    description: "Total number of HTTP requests processed"
);

// GOOD — low-cardinality attributes only
requestCounter.Add(1, new TagList
{
    { "http.request.method", "GET" },
    { "http.response.status_code", 200 }
});

// BAD — userId has unbounded cardinality; creates millions of series
requestCounter.Add(1, new TagList { { "user.id", userId } });  // NEVER do this
```

### UpDownCounter

```csharp
var activeConnections = _meter.CreateUpDownCounter<long>(
    "db.client.connections.usage",
    unit: "{connection}",
    description: "Number of active database connections"
);

activeConnections.Add(1, new TagList { { "pool.name", "primary" } });   // acquired
activeConnections.Add(-1, new TagList { { "pool.name", "primary" } });  // released
```

### Histogram

```csharp
var requestDuration = _meter.CreateHistogram<double>(
    "http.server.request.duration",
    unit: "ms",
    description: "Duration of HTTP server requests"
);

requestDuration.Record(42.5, new TagList { { "http.route", "/api/v1/users" } });
```

### Synchronous Gauge (.NET 9+ only)

> **Note:** `Meter.CreateGauge<T>()` requires .NET 9+. On .NET 8, use `ObservableGauge` with a callback that reads from an in-memory field updated at the measurement point.

Use when you need to record a value imperatively at a specific point in time (e.g., per-request cache hit ratio, current temperature reading).

```csharp
// GOOD — synchronous gauge (.NET 9+): call Record() when the value changes
var cacheHitRatio = _meter.CreateGauge<double>(
    "cache.hit.ratio",
    unit: "1",
    description: "Current cache hit ratio"
);

cacheHitRatio.Record(0.87, new TagList { { "cache.name", "session" } });
```

```csharp
// .NET 8 alternative — use ObservableGauge backed by an in-memory field
private double _currentCacheHitRatio;

_meter.CreateObservableGauge<double>(
    "cache.hit.ratio",
    () => _currentCacheHitRatio,
    unit: "1",
    description: "Current cache hit ratio"
);

// Update the field at the measurement point (e.g., per-request)
_currentCacheHitRatio = 0.87;
```

### Observable Gauge

Use when the value is best read on-demand from an in-memory source (memory usage, queue depth, etc.).

```csharp
// GOOD — observable gauge: callback reads pre-computed in-memory value
_meter.CreateObservableGauge<double>(
    "system.memory.utilization",
    () => GC.GetGCMemoryInfo().MemoryLoadBytes / (double)GC.GetGCMemoryInfo().TotalAvailableMemoryBytes,
    unit: "1",
    description: "Current memory utilization ratio"
);
```

> **Observable callback rule:** The callback is invoked by the SDK on every export interval (default: 60 s).
> Do NOT perform blocking I/O or expensive computation inside it. Read from an in-memory value and return immediately.

### Observable Counter

```csharp
long _totalBytesRead = 0;

_meter.CreateObservableCounter<long>(
    "io.bytes.read",
    () => Interlocked.Read(ref _totalBytesRead),
    unit: "By"
);
```

### Observable UpDownCounter

```csharp
_meter.CreateObservableUpDownCounter<long>(
    "thread.pool.active",
    () => ThreadPool.ThreadCount,
    unit: "{thread}"
);
```

## Cardinality Warning

```csharp
// BAD — userId has unbounded cardinality; creates millions of series in the backend
requestCounter.Add(1, new TagList
{
    { "user.id", userId }       // NEVER use per-request or per-user values
});

// GOOD — low-cardinality attributes only
requestCounter.Add(1, new TagList
{
    { "http.request.method", "GET" },
    { "user.tier", "premium" }  // bounded set of values
});
```

Rules:
- Never use `userId`, `requestId`, `traceId`, email, or any per-request value as a metric tag
- Maximum ~100 unique values per tag key
- Each unique tag combination is a separate series in the collector backend

## Naming Rules

- Dot notation: `http.server.request.duration` not `http_server_request_duration`
- No service name in metric name: `web_backend_latency` → BAD
- No units in metric name: `latency_ms` → BAD; set `unit: "ms"` instead
- Check `otel-semantic-conventions` before inventing custom names

## Cross-Skill Pointers

| Topic | Skill |
|-------|-------|
| Metric vs span vs log decision | `signal-choice-advisor` |
| Attribute key naming | `otel-semantic-conventions` |
| All instrument types table | `references/otel-reference.md` |
| Cardinality / naming audit | `tsuga-audit-metrics` |
