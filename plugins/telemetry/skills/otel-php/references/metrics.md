# Metrics — PHP OTel

> **Last verified:** 2026-03-23 | SDK: `open-telemetry/opentelemetry-php` 1.13.0 | exporter-otlp 1.4.0

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

## All Instruments with PHP API

### Counter

```php
<?php

use OpenTelemetry\API\Globals;

$meter = Globals::meterProvider()->getMeter('my-service', '1.0.0');

// GOOD — dot notation name, unit set separately, low-cardinality attributes
$requestCounter = $meter->createCounter(
    'http.server.request.count',
    '{request}',
    'Total number of HTTP requests processed'
);

$requestCounter->add(1, [
    'http.request.method'       => 'GET',
    'http.response.status_code' => 200,
]);
```

### UpDownCounter

```php
// GOOD — tracks active connections (can go up or down)
$activeConnections = $meter->createUpDownCounter(
    'db.client.connections.usage',
    '{connection}',
    'Number of active database connections'
);

$activeConnections->add(1, ['pool.name' => 'primary']);   // acquired
$activeConnections->add(-1, ['pool.name' => 'primary']);  // released
```

### Histogram

```php
// GOOD — distribution of request duration
$requestDuration = $meter->createHistogram(
    'http.server.request.duration',
    'ms',
    'Duration of HTTP server requests'
);

$requestDuration->record(42.5, ['http.route' => '/api/v1/users']);
```

### Synchronous Gauge

Use when you need to record a value imperatively — e.g., per-request thread count, cache hit ratio, queue depth at a point in time.

```php
// GOOD — synchronous gauge: call set() when the value changes
$cacheHitRatio = $meter->createGauge(
    'cache.hit.ratio',
    '1',
    'Current cache hit ratio'
);

// Call set() whenever the value changes
$cacheHitRatio->record(0.87, ['cache.name' => 'session']);
```

> The PHP SDK method for synchronous gauge is `createGauge()`, which returns a `GaugeInterface`. Call `record()` to set the current value.

### Observable Gauge

Use when the value is best read on-demand from an in-memory source (memory usage, queue depth, etc.).

```php
// GOOD — observable gauge: callback reads pre-computed value
$observableGauge = $meter->createObservableGauge(
    'php.memory.usage',
    'By',
    'Current PHP memory usage'
);

$observableGauge->observe(static function (\OpenTelemetry\API\Metrics\ObserverInterface $observer): void {
    $observer->observe(memory_get_usage(true), ['type' => 'real']);
});
```

> **Observable callback rule:** The callback is invoked by the metric reader on every export interval. Do NOT perform blocking I/O or slow computation inside it. Read from an already-computed in-memory value and return immediately.

### Observable Counter

```php
// Track total bytes processed — monotonically increasing
$totalBytesProcessed = 0;

$observableCounter = $meter->createObservableCounter(
    'io.bytes.read',
    'By',
    'Total bytes read from input'
);

$observableCounter->observe(static function (\OpenTelemetry\API\Metrics\ObserverInterface $observer) use (&$totalBytesProcessed): void {
    $observer->observe($totalBytesProcessed, []);
});
```

### Observable UpDownCounter

```php
// Track active worker threads in a pool
$meter->createObservableUpDownCounter(
    'thread.pool.active',
    '{thread}',
    'Number of active worker threads'
)->observe(static function (\OpenTelemetry\API\Metrics\ObserverInterface $observer) use ($pool): void {
    $observer->observe($pool->getActiveCount(), []);
});
```

## Cardinality Warning

```php
// BAD — userId has unbounded cardinality; creates millions of series
$requestCounter->add(1, [
    'user.id' => $userId   // NEVER do this
]);

// GOOD — low-cardinality attributes only
$requestCounter->add(1, [
    'http.request.method' => 'GET',
    'user.tier'           => 'premium',   // bounded set
]);
```

**Rules:**
- Never use `userId`, `requestId`, `traceId`, email, or any per-request value as a metric attribute
- Maximum ~100 unique values per attribute key
- Each unique attribute combination is a separate series in the collector backend

## Naming Rules

- Dot notation: `http.server.request.duration` not `http_server_request_duration`
- No service name in metric name: `web_backend_latency` → BAD
- No units in metric name: `latency_ms` → BAD; set the `$unit` parameter instead
- Check `otel-semantic-conventions` before inventing custom names

## Cross-Skill Pointers

| Topic | Skill |
|-------|-------|
| Metric vs span vs log decision | `signal-choice-advisor` |
| Attribute key naming | `otel-semantic-conventions` |
| All instrument types table | `references/otel-reference.md` |
| Cardinality / naming audit | `tsuga-audit-metrics` |
