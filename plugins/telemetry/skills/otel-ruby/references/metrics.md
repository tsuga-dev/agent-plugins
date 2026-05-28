# Metrics — Ruby OTel

> Last verified: 2026-03-23 | SDK: opentelemetry-sdk 1.10.0 / opentelemetry-exporter-otlp 0.32.0

> **Stability note:** Ruby OTel Metrics are Development status. Suitable for instrumentation tasks; verify the [opentelemetry-ruby metrics changelog](https://github.com/open-telemetry/opentelemetry-ruby/blob/main/metrics_sdk/CHANGELOG.md) before relying on metrics in production.

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

## All Instruments with Ruby API

Get a meter first:

```ruby
meter = OpenTelemetry.meter_provider.meter('my-service', version: '1.0.0')
```

### Counter

```ruby
# GOOD — counts requests with low-cardinality attributes
request_counter = meter.create_counter(
  'http.server.request.count',
  unit: '{request}',
  description: 'Total number of HTTP requests processed'
)

request_counter.add(1, attributes: {
  'http.request.method' => 'GET',
  'http.response.status_code' => 200
})
```

### UpDownCounter

```ruby
# GOOD — tracks active connections (goes up and down)
active_connections = meter.create_up_down_counter(
  'db.client.connections.usage',
  unit: '{connection}',
  description: 'Number of active database connections'
)

active_connections.add(1, attributes: { 'pool.name' => 'primary' })    # acquired
active_connections.add(-1, attributes: { 'pool.name' => 'primary' })   # released
```

### Histogram

```ruby
# GOOD — records request duration distribution
request_duration = meter.create_histogram(
  'http.server.request.duration',
  unit: 'ms',
  description: 'Duration of HTTP server requests'
)

request_duration.record(42.5, attributes: { 'http.route' => '/api/v1/users' })
```

### Synchronous Gauge

Use when you need to record a value imperatively at the moment it changes — for example, a per-request computed ratio or a value tied to a specific operation.

```ruby
# GOOD — synchronous gauge: call .record() when the value changes
cache_hit_ratio = meter.create_gauge(
  'cache.hit.ratio',
  unit: '1',
  description: 'Current cache hit ratio for this request'
)

cache_hit_ratio.record(0.87, attributes: { 'cache.name' => 'session' })
```

### Observable Gauge

Use when the value is best read on-demand from an in-memory source (queue depth, memory usage, etc.).

```ruby
# GOOD — observable gauge: callback reads pre-computed value
meter.create_observable_gauge(
  'process.memory.rss',
  unit: 'By',
  description: 'Resident set size of the Ruby process'
) do |result|
  result.observe(
    `ps -o rss= -p #{Process.pid}`.strip.to_i * 1024,
    attributes: {}
  )
end
```

> **Observable callback rule:** The block is called by the metrics reader on each export interval (default: 60 s). Do NOT perform blocking I/O or expensive computation inside it. Read from an already-computed in-memory value and return immediately.

### Observable Counter

```ruby
total_bytes_sent = 0   # maintained by your application logic

meter.create_observable_counter(
  'io.bytes.sent',
  unit: 'By',
  description: 'Total bytes sent'
) do |result|
  result.observe(total_bytes_sent, attributes: {})
end
```

### Observable UpDownCounter

```ruby
meter.create_observable_up_down_counter(
  'thread.pool.active',
  unit: '{thread}',
  description: 'Number of active threads in pool'
) do |result|
  result.observe(Sidekiq::Stats.new.workers_size, attributes: {})
end
```

## Cardinality Warning

```ruby
# BAD — user_id has unbounded cardinality; creates millions of series
request_counter.add(1, attributes: {
  'user.id' => user_id    # NEVER do this
})

# GOOD — low-cardinality attributes only
request_counter.add(1, attributes: {
  'http.request.method' => 'GET',
  'user.tier' => 'premium'    # bounded set of values
})
```

**Rules:**
- Never use `user_id`, `request_id`, `trace_id`, email, or any per-request value as a metric attribute
- Maximum ~100 unique values per attribute key
- Each unique attribute combination is a separate series in the backend

## Naming Rules

- Dot notation: `http.server.request.duration` not `http_server_request_duration`
- No service name in metric name: `web_backend_latency` → BAD
- No units in metric name: `latency_ms` → BAD; set `unit: 'ms'` instead
- Check `otel-semantic-conventions` before inventing custom names

## Cross-Skill Pointers

| Topic | Skill |
|-------|-------|
| Metric vs span vs log decision | `signal-choice-advisor` |
| Attribute key naming | `otel-semantic-conventions` |
| All instrument types table | `references/otel-reference.md` |
| Cardinality / naming audit | `tsuga-audit-metrics` |
