# Metrics — Java OTel

> **Last verified:** 2026-03-23 | SDK: `opentelemetry-bom` 1.60.1

## Instrument Selection

| Question | Answer | Instrument |
|----------|--------|------------|
| Counts events that only go up? | Yes | **Counter** |
| Counts things that go up and down? | Yes | **UpDownCounter** |
| Measures distribution (latency, size)? | Yes | **Histogram** |
| Measures a current spot value synchronously (call `.set()` on each measurement)? | Yes | **Synchronous Gauge** |
| Measures a current spot value via callback at collection time? | Yes | **Observable Gauge** |
| Tracks a cumulative total sampled at collection? | Yes | **Observable Counter** |
| Tracks fluctuating total sampled at collection? | Yes | **Observable UpDownCounter** |

> Unsure between metric / span / log? → `signal-choice-advisor`

## All Instruments with Java API

### Counter

```java
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.api.metrics.LongCounter;
import io.opentelemetry.api.metrics.Meter;

Meter meter = GlobalOpenTelemetry.getMeter("com.myapp");

LongCounter requestCounter = meter.counterBuilder("http.server.request.count")
    .setDescription("Total number of requests processed")
    .setUnit("{request}")
    .build();

// Record: verbose but type-safe Attributes API
requestCounter.add(1, Attributes.of(
    AttributeKey.stringKey("http.request.method"), "GET",
    AttributeKey.longKey("http.response.status_code"), 200L
));

// Double variant
meter.counterBuilder("bytes.sent")
    .ofDoubles()
    .setUnit("By")
    .build();
```

### UpDownCounter

```java
import io.opentelemetry.api.metrics.LongUpDownCounter;

LongUpDownCounter activeConnections = meter.upDownCounterBuilder("db.client.connections.usage")
    .setDescription("Number of active database connections")
    .setUnit("{connection}")
    .build();

activeConnections.add(1, Attributes.of(AttributeKey.stringKey("pool.name"), "primary"));   // acquired
activeConnections.add(-1, Attributes.of(AttributeKey.stringKey("pool.name"), "primary"));  // released
```

### Histogram

```java
import io.opentelemetry.api.metrics.DoubleHistogram;

DoubleHistogram requestDuration = meter.histogramBuilder("http.server.request.duration")
    .setDescription("Duration of HTTP server requests")
    .setUnit("s")
    .build();

requestDuration.record(42.5, Attributes.of(
    AttributeKey.stringKey("http.route"), "/api/v1/users"
));

// Long variant
meter.histogramBuilder("request.body.size")
    .ofLongs()
    .setUnit("By")
    .build();
```

### Synchronous Gauge

Stable since SDK 1.38. Use when you need to record a value imperatively (e.g., per-request thread count, cache hit ratio per request).

```java
import io.opentelemetry.api.metrics.DoubleGauge;

// GOOD — synchronous gauge: call .set() when the value changes
// gaugeBuilder() returns DoubleGaugeBuilder; .build() gives DoubleGauge (stable since SDK 1.38)
DoubleGauge cacheHitRatio = meter.gaugeBuilder("cache.hit.ratio")
    .setDescription("Current cache hit ratio")
    .setUnit("1")
    .build();

cacheHitRatio.set(0.87, Attributes.of(AttributeKey.stringKey("cache.name"), "session"));
```

### Observable Gauge

Use when the value is best read on-demand from an in-memory source (JVM heap, queue depth, etc.).

```java
// GOOD — observable gauge: callback reads pre-computed value
meter.gaugeBuilder("jvm.memory.heap.used")
    .setDescription("Current JVM heap memory used")
    .setUnit("By")
    .buildWithCallback(measurement ->
        measurement.record(
            Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory(),
            Attributes.empty()
        )
    );
```

> **Observable callback rule:** The callback is invoked by `PeriodicMetricReader` on every export
> interval (default: 60 s). Do NOT perform blocking I/O or expensive computation inside it.
> Read from an already-computed `AtomicLong` or similar in-memory value and return immediately.

### Observable Counter

```java
AtomicLong totalBytesRead = new AtomicLong(0);

meter.counterBuilder("io.bytes.read")
    .setUnit("By")
    .buildWithCallback(measurement ->
        measurement.record(totalBytesRead.get(), Attributes.empty())
    );
```

### Observable UpDownCounter

```java
meter.upDownCounterBuilder("thread.pool.active")
    .setUnit("{thread}")
    .buildWithCallback(measurement ->
        measurement.record(threadPool.getActiveCount(), Attributes.empty())
    );
```

## Java Attributes API

Java requires explicit `AttributeKey` types — unlike Python's dict or Go's variadic pairs.

```java
// GOOD
Attributes attrs = Attributes.of(
    AttributeKey.stringKey("http.request.method"), "GET",
    AttributeKey.longKey("http.response.status_code"), 200L,
    AttributeKey.booleanKey("error"), false
);

// GOOD — builder for 3+ attributes
Attributes attrs = Attributes.builder()
    .put("service.tier", "premium")
    .put("region", "us-east-1")
    .build();
```

## Cardinality Warning

```java
// BAD — userId has unbounded cardinality; creates millions of series
requestCounter.add(1, Attributes.of(
    AttributeKey.stringKey("user.id"), userId   // NEVER do this
));

// GOOD — low-cardinality attributes only
requestCounter.add(1, Attributes.of(
    AttributeKey.stringKey("http.request.method"), "GET",
    AttributeKey.stringKey("user.tier"), "premium"   // bounded set
));
```

**Rules:**
- Never use `userId`, `requestId`, `traceId`, email, or any per-request value as a metric attribute
- Maximum ~100 unique values per attribute key
- Each unique attribute combination is a separate series in the collector backend

## Naming Rules

- Dot notation: `http.server.request.duration` not `http_server_request_duration`
- No service name in metric name: `web_backend_latency` → BAD
- No units in metric name: `latency_ms` → BAD; set `.setUnit("ms")` instead
- Check `otel-semantic-conventions` before inventing custom names

## Cross-Skill Pointers

| Topic | Skill |
|-------|-------|
| Metric vs span vs log decision | `signal-choice-advisor` |
| Attribute key naming | `otel-semantic-conventions` |
| All instrument types table | `references/otel-reference.md` |
| Cardinality / naming audit | `tsuga-audit-metrics` |
