# Async Messaging — Ruby OTel

> Last verified: 2026-03-23 | SDK: opentelemetry-sdk 1.10.0 / opentelemetry-exporter-otlp 0.32.0

## Context Model: Use Span Links, Not Parent-Child

Async CONSUMER spans must use **span Links** to the producer span — not parent-child relationships. The producer and consumer are separate operations in separate traces.

```ruby
tracer = OpenTelemetry.tracer_provider.tracer('my-service')

# BAD — makes consumer appear as a child of the producer span; merges unrelated traces
producer_ctx = OpenTelemetry.propagation.extract(message_headers)
tracer.in_span('process orders', with_parent: producer_ctx) do |span|
  # span's parent is the producer's span — WRONG
end

# GOOD — new root span linked to producer for cross-trace navigation
producer_ctx = OpenTelemetry.propagation.extract(message_headers)
producer_span = OpenTelemetry::Trace.current_span(producer_ctx)
link = OpenTelemetry::Trace::Link.new(producer_span.context)

tracer.in_span(
  'receive orders',
  kind: OpenTelemetry::Trace::SpanKind::CONSUMER,
  links: [link]
) do |span|
  span.set_attribute('messaging.system', 'kafka')
  span.set_attribute('messaging.destination.name', 'orders')
  span.set_attribute('messaging.operation', 'receive')
  process_message(message)
end
```

## Span Naming

Pattern: `{operation} {destination}` — e.g., `publish orders`, `receive payments`, `process user-events`

| BAD | GOOD |
|-----|------|
| `kafkaConsumer` | `receive user-events` |
| `sendMessage` | `publish orders` |
| `processJob` | `process payment-queue` |

## Required `messaging.*` Semconv Attributes

| Attribute | Required | Example |
|-----------|----------|---------|
| `messaging.system` | Yes | `kafka`, `rabbitmq` |
| `messaging.destination.name` | Yes | `orders`, `user-events` |
| `messaging.operation` | Yes | `publish`, `receive`, `process` |
| `messaging.message.id` | Recommended | `"msg-abc-123"` |

> Check `otel-semantic-conventions` for the full `messaging.*` namespace before adding custom attributes.

## Kafka via ruby-kafka

### Producer

```ruby
require 'kafka'
require 'opentelemetry'

def publish_message(producer, topic, payload)
  headers = {}
  OpenTelemetry.propagation.inject(headers)   # injects traceparent into headers hash

  tracer = OpenTelemetry.tracer_provider.tracer('my-service')
  tracer.in_span(
    "publish #{topic}",
    kind: OpenTelemetry::Trace::SpanKind::PRODUCER
  ) do |span|
    span.set_attribute('messaging.system', 'kafka')
    span.set_attribute('messaging.destination.name', topic)
    span.set_attribute('messaging.operation', 'publish')

    producer.produce(payload, topic: topic, headers: headers)
    producer.deliver_messages
  end
end
```

### Consumer

```ruby
require 'kafka'
require 'opentelemetry'

def process_kafka_message(message)
  tracer = OpenTelemetry.tracer_provider.tracer('my-service')

  # Extract producer context from message headers
  producer_ctx = OpenTelemetry.propagation.extract(message.headers)
  producer_span = OpenTelemetry::Trace.current_span(producer_ctx)
  link = OpenTelemetry::Trace::Link.new(producer_span.context)

  # GOOD — new root span linked to producer; do NOT use with_parent: producer_ctx
  tracer.in_span(
    "receive #{message.topic}",
    kind: OpenTelemetry::Trace::SpanKind::CONSUMER,
    links: [link]
  ) do |span|
    span.set_attribute('messaging.system', 'kafka')
    span.set_attribute('messaging.destination.name', message.topic)
    span.set_attribute('messaging.operation', 'receive')
    span.set_attribute('messaging.kafka.partition', message.partition)
    span.set_attribute('messaging.kafka.offset', message.offset)

    handle_message(message.value)
  rescue => e
    span.record_exception(e)
    span.status = OpenTelemetry::Trace::Status.error("kafka processing failed: #{e.message}")
    raise
  end
end
```

## Kafka via rdkafka-ruby

The inject/extract pattern is the same as ruby-kafka. `rdkafka` messages carry headers as a `Rdkafka::Consumer::Headers` object. Extract using `message.headers` (returns a hash-like object that `OpenTelemetry.propagation.extract` accepts directly).

```ruby
# Producer — inject into headers hash before produce
headers = {}
OpenTelemetry.propagation.inject(headers)
producer.produce(topic: topic, payload: payload, headers: headers)
producer.flush

# Consumer — extract from delivery message headers
producer_ctx = OpenTelemetry.propagation.extract(message.headers)
producer_span = OpenTelemetry::Trace.current_span(producer_ctx)
link = OpenTelemetry::Trace::Link.new(producer_span.context)

tracer.in_span("receive #{message.topic}", kind: OpenTelemetry::Trace::SpanKind::CONSUMER, links: [link]) do |span|
  # ...
end
```

## Sidekiq

> **Important:** Context does NOT flow across Sidekiq jobs automatically. The Sidekiq middleware runs in a separate process and a separate thread. W3C propagation headers must be serialized into job arguments by the caller and deserialized by the worker.

### With `opentelemetry-instrumentation-sidekiq` (recommended)

When the `opentelemetry-instrumentation-sidekiq` gem is installed and `c.use_all` (or `c.use 'OpenTelemetry::Instrumentation::Sidekiq'`) is in the configure block, propagation is handled automatically. The middleware injects headers into job args on enqueue and extracts them on execution.

Verify it is active:

```bash
bundle exec gem list | grep opentelemetry-instrumentation-sidekiq
```

### Manual Sidekiq Propagation

Use when the instrumentation gem is not available or for custom context requirements.

**Caller (enqueue side):**

```ruby
class OrderWorker
  include Sidekiq::Worker

  def self.enqueue_with_tracing(order_id)
    # Serialize W3C headers into job arguments
    carrier = {}
    OpenTelemetry.propagation.inject(carrier)
    perform_async(order_id, carrier)
  end
end
```

**Worker (process side):**

```ruby
class OrderWorker
  include Sidekiq::Worker

  def perform(order_id, otel_carrier = {})
    tracer = OpenTelemetry.tracer_provider.tracer('my-service')

    # Extract producer context
    producer_ctx = OpenTelemetry.propagation.extract(otel_carrier)
    producer_span = OpenTelemetry::Trace.current_span(producer_ctx)
    link = OpenTelemetry::Trace::Link.new(producer_span.context)

    # GOOD — new root span linked to the caller's trace
    tracer.in_span(
      'process order',
      kind: OpenTelemetry::Trace::SpanKind::CONSUMER,
      links: [link]
    ) do |span|
      span.set_attribute('messaging.system', 'sidekiq')
      span.set_attribute('messaging.destination.name', 'order_worker')
      span.set_attribute('messaging.operation', 'process')
      span.set_attribute('order.id', order_id)

      process_order(order_id)
    rescue => e
      span.record_exception(e)
      span.status = OpenTelemetry::Trace::Status.error("order processing failed: #{e.message}")
      raise
    end
  end
end
```

## Auto-Instrumentation Coverage

| System | Auto-instrumented? | Notes |
|--------|--------------------|-------|
| Rack / Rails HTTP | Yes | `opentelemetry-instrumentation-rack` |
| Net::HTTP | Yes | `opentelemetry-instrumentation-net_http` |
| Faraday | Yes | `opentelemetry-instrumentation-faraday` |
| Sidekiq | Yes | `opentelemetry-instrumentation-sidekiq` — context propagated via middleware |
| ruby-kafka | Partial | `opentelemetry-instrumentation-ruby_kafka` available; check gem version |
| rdkafka | No | Manual inject/extract required |
| Active Record | Yes | `opentelemetry-instrumentation-active_record` |

For systems without auto-instrumentation, use the manual inject/extract pattern shown above.

## Verification

```bash
# Check producer spans
tsuga spans search --query "context.service.name:<producer-service> messaging.system:kafka" --max-results 5

# Check consumer spans — verify links field is present, not parent-child
tsuga spans search --query "context.service.name:<consumer-service> messaging.operation:receive" --max-results 5

# Verify Sidekiq worker spans
tsuga spans search --query "context.service.name:<worker-service> messaging.system:sidekiq" --max-results 5
```

In the consumer span output, verify:
- `parentSpanId` is empty or null (new root — not a child)
- `links` array contains the producer's `spanId`
