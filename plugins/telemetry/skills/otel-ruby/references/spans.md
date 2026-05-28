# Span Naming, Kind, and Status Rules — Ruby

> Last verified: 2026-03-23 | SDK: opentelemetry-sdk 1.10.0 / opentelemetry-exporter-otlp 0.32.0
>
> See also: `otel-semantic-conventions` skill for attribute naming; `otel-reference.md` for instrument types.

## Span Naming

**Pattern:** `{verb} {object}` in sentence case. Low-cardinality — no IDs, no raw paths.

| BAD | GOOD | Why |
|-----|------|-----|
| `"GET /users/#{user_id}/orders"` | `GET /users/{id}/orders` | String interpolation creates unbounded cardinality |
| `processOrder` | `process order` | Space-separated verb-object |

```ruby
# BAD
tracer.in_span("GET /users/#{user_id}/orders") { ... }

# GOOD
tracer.in_span("GET /users/{id}/orders", attributes: { 'user.id' => user_id }) { ... }
```

## Span Kind Decision Tree

| Scenario | Kind |
|----------|------|
| Inbound HTTP/gRPC | `OpenTelemetry::Trace::SpanKind::SERVER` |
| Outbound HTTP, DB | `OpenTelemetry::Trace::SpanKind::CLIENT` |
| Publishing to queue | `OpenTelemetry::Trace::SpanKind::PRODUCER` |
| Consuming from queue | `OpenTelemetry::Trace::SpanKind::CONSUMER` |
| Local logic | `OpenTelemetry::Trace::SpanKind::INTERNAL` |

```ruby
tracer.in_span('POST /orders', kind: OpenTelemetry::Trace::SpanKind::SERVER) do |span|
  # ...
end
```

## HTTP Status → Span Status Mapping

| Span Kind | HTTP 4xx | HTTP 5xx |
|-----------|----------|----------|
| SERVER | **UNSET** | ERROR |
| CLIENT | **ERROR** | ERROR |

```ruby
# Server span: 400 is NOT an error
if status_code >= 500
  span.status = OpenTelemetry::Trace::Status.error("Internal server error")
end

# Client span: 4xx IS an error
if status_code >= 400
  span.status = OpenTelemetry::Trace::Status.error("HTTP #{status_code}")
end
```

## Headless Operations Pattern

```ruby
# BAD: Sidekiq worker creates child spans with no parent
class NightlyCleanupJob
  include Sidekiq::Worker
  def perform
    tracer.in_span("query-stale-records") { ... }  # Orphan!
  end
end

# GOOD: create SERVER root span
class NightlyCleanupJob
  include Sidekiq::Worker
  def perform
    tracer.in_span("nightly-cleanup",
      kind: OpenTelemetry::Trace::SpanKind::SERVER,
      attributes: { 'task.name' => 'nightly-cleanup', 'task.trigger' => 'sidekiq' }
    ) do |root_span|
      tracer.in_span("query-stale-records") { |child| ... }
    end
  end
end
```

## Span Hygiene Rules

- **< 10 INTERNAL spans per trace**
- **< 20 spans under 5ms**
- **No orphan spans**
- **Root spans cannot be CLIENT or PRODUCER**
- **Error spans must include a description**

## Span Budget

| Signal | Per-request budget | Notes |
|--------|--------------------|-------|
| Incoming HTTP request | 1 SERVER span | Auto-instrumented by `opentelemetry-instrumentation-rack` |
| Outbound HTTP / gRPC call | 1 CLIENT span per call | Auto-instrumented by `opentelemetry-instrumentation-net_http` / Faraday |
| DB query | 1 CLIENT span per query | Auto-instrumented by `opentelemetry-instrumentation-active_record` |
| External service call | 1 CLIENT span | — |
| Business transaction (order.place, payment.charge) | 1 INTERNAL span | Use `in_span` block or manual span |
| Sidekiq job | 1 CONSUMER root span | Auto-instrumented by `opentelemetry-instrumentation-sidekiq` |
| Internal helper function | ❌ Skip | Unless measurably slow or failure-prone |
| Utility called thousands of times per request | ❌ Skip | Creates noise; use metric instead |
| Loop iteration (per-item span in a batch) | ⚠️ Only if needed | Confirm sampling is in place first |

Anti-pattern: instrumenting every method. The goal is minimum spans needed to diagnose failures and measure latency at service boundaries.

## Workflow Boundaries

**Rule:** Same user operation across services → continue the trace (propagate W3C `traceparent`). Separate operations, separate queue deliveries, or separate scheduled jobs → new root span.

Never propagate a parent context from one unrelated job into another.

### Continue the trace (outbound HTTP call)

```ruby
# Inject current context into outbound HTTP headers
headers = {}
OpenTelemetry.propagation.inject(headers)

uri = URI('https://downstream-service/api')
req = Net::HTTP::Get.new(uri)
headers.each { |k, v| req[k] = v }
Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') { |http| http.request(req) }
```

### New root span (scheduled job or cron task)

```ruby
tracer = OpenTelemetry.tracer_provider.tracer('my-service')

# in_span with no with_parent: creates a true root span
tracer.in_span(
  'nightly-cleanup',
  kind: OpenTelemetry::Trace::SpanKind::SERVER,
  attributes: { 'task.name' => 'nightly-cleanup', 'task.trigger' => 'cron' }
) do |span|
  do_cleanup_work
end
```

### Related but not parent-child (async / queue delivery)

```ruby
# addLink connects traces for navigation without making one a child of the other
producer_ctx  = OpenTelemetry.propagation.extract(message_headers)
producer_span = OpenTelemetry::Trace.current_span(producer_ctx)
link          = OpenTelemetry::Trace::Link.new(producer_span.context)

tracer.in_span(
  'process order',
  kind: OpenTelemetry::Trace::SpanKind::CONSUMER,
  links: [link]   # link to producer trace — NOT with_parent:
) do |span|
  # ...
end
```

> **→** `references/async-messaging.md` — full Kafka, Sidekiq, rdkafka patterns with semconv.
