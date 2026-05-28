# Metrics — Node.js OTel

> **Last verified:** 2026-03-23 | SDK: `@opentelemetry/sdk-node` 0.213.x / `@opentelemetry/api` 1.9.x

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

## All Instruments with Node.js API

### Counter

```javascript
const { metrics } = require('@opentelemetry/api');

const meter = metrics.getMeter('com.myapp');

// GOOD — low-cardinality attributes; description and unit set
const requestCounter = meter.createCounter('http.server.request.count', {
  description: 'Total number of requests processed',
  unit: '{request}',
});

requestCounter.add(1, {
  'http.request.method': 'GET',
  'http.response.status_code': 200,
});

// BAD — userId has unbounded cardinality; creates millions of series
requestCounter.add(1, { 'user.id': userId });  // NEVER do this
```

### UpDownCounter

```javascript
const activeConnections = meter.createUpDownCounter('db.client.connections.usage', {
  description: 'Number of active database connections',
  unit: '{connection}',
});

activeConnections.add(1, { 'pool.name': 'primary' });   // acquired
activeConnections.add(-1, { 'pool.name': 'primary' });  // released
```

### Histogram

```javascript
const requestDuration = meter.createHistogram('http.server.request.duration', {
  description: 'Duration of HTTP server requests',
  unit: 'ms',
});

requestDuration.record(42.5, { 'http.route': '/api/v1/users' });
```

### Synchronous Gauge

Use when you need to record a value imperatively at measurement time — not via a callback.

```javascript
// GOOD — synchronous gauge: call .record() when the value is known
const cacheHitRatio = meter.createGauge('cache.hit.ratio', {
  description: 'Current cache hit ratio',
  unit: '1',
});

// Called per-request or per-operation when the value is known
cacheHitRatio.record(0.87, { 'cache.name': 'session' });
```

**BAD — using a Counter for a value that fluctuates:**

```javascript
// WRONG — Counter only goes up; cannot represent a ratio that falls
const badRatio = meter.createCounter('cache.hit.ratio');
badRatio.add(0.87);  // meaningless for a ratio that can decrease
```

### Observable Gauge

Use when the value is best read on-demand from an in-memory source (memory usage, queue depth, etc.).

```javascript
// GOOD — observable gauge: callback reads pre-computed value
const memGauge = meter.createObservableGauge('process.memory.heap.used', {
  description: 'Current heap memory used',
  unit: 'By',
});

memGauge.addCallback((result) => {
  const mem = process.memoryUsage();
  result.observe(mem.heapUsed, {});
});
```

> **Observable callback rule:** The callback is invoked by `PeriodicExportingMetricReader` on every
> export interval (default: 60 s). Do NOT perform blocking I/O or expensive computation inside it.
> Read from an already-computed in-memory value and return immediately.

### Observable Counter

```javascript
let totalBytesRead = 0;

const bytesReadCounter = meter.createObservableCounter('io.bytes.read', {
  unit: 'By',
});

bytesReadCounter.addCallback((result) => {
  result.observe(totalBytesRead, {});
});
```

### Observable UpDownCounter

```javascript
const activeTasksGauge = meter.createObservableUpDownCounter('thread.pool.active', {
  unit: '{thread}',
});

activeTasksGauge.addCallback((result) => {
  result.observe(threadPool.getActiveCount(), {});
});
```

## Cardinality Warning

```javascript
// BAD — userId has unbounded cardinality; creates millions of time series
requestCounter.add(1, { 'user.id': userId });       // NEVER
requestCounter.add(1, { 'request.id': requestId }); // NEVER
requestCounter.add(1, { 'session.id': sessionId }); // NEVER

// GOOD — low-cardinality attributes only (bounded set of values)
requestCounter.add(1, {
  'http.request.method': 'GET',
  'http.response.status_code': 200,
  'user.tier': 'premium',   // bounded: free / premium / enterprise
});
```

**Rules:**
- Never use `userId`, `requestId`, `traceId`, email, IP address, or any per-request value as a metric attribute
- Maximum ~100 unique values per attribute key
- Each unique attribute combination is a separate series in the collector backend

## Naming Rules

- Dot notation: `http.server.request.duration` not `http_server_request_duration`
- No service name in metric name: `web_backend_latency` → BAD
- No units in metric name: `latency_ms` → BAD; set `unit: 'ms'` instead
- No environment in metric name: `prod_errors` → BAD
- Check `otel-semantic-conventions` before inventing custom names

## Cross-Skill Pointers

| Topic | Skill |
|-------|-------|
| Metric vs span vs log decision | `signal-choice-advisor` |
| Attribute key naming | `otel-semantic-conventions` |
| All instrument types table | `references/otel-reference.md` |
| Cardinality / naming audit | `tsuga-audit-metrics` |
