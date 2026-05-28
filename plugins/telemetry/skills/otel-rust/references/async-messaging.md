# Async Messaging — Rust OTel

> Last verified: 2026-03-23 | SDK: opentelemetry 0.31.0 / opentelemetry-otlp 0.31.0

## Context Model: Use Span Links, Not Parent-Child

Async CONSUMER spans must use **span Links** to the producer span — not parent-child relationships. The producer and consumer are separate operations in separate traces.

```rust
// BAD — makes consumer appear as a child of the producer's trace
let span = tracing::info_span!("receive orders");
{
    use tracing_opentelemetry::OpenTelemetrySpanExt;
    span.set_parent(extracted_producer_context);  // WRONG — merges workflows
}

// GOOD — new root span linked to producer for cross-trace navigation
let span = tracing::info_span!("receive orders");
{
    use tracing_opentelemetry::OpenTelemetrySpanExt;
    let producer_span_ctx = extracted_producer_context.span().span_context().clone();
    if producer_span_ctx.is_valid() {
        span.add_link(producer_span_ctx);  // link, not parent
    }
    // Do NOT call span.set_parent(extracted_producer_context)
}
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
| `messaging.system` | Yes | `kafka`, `rabbitmq`, `aws_sqs` |
| `messaging.destination.name` | Yes | `orders`, `user-events` |
| `messaging.operation` | Yes | `publish`, `receive`, `process` |
| `messaging.message.id` | Recommended | `"msg-abc-123"` |

> Check `otel-semantic-conventions` for the full `messaging.*` namespace before adding custom attributes.

## Auto-Instrumentation Coverage

| System | Auto-instrumented? |
|--------|-------------------|
| Kafka (rdkafka) | No — all manual |
| AMQP (lapin) | No — all manual |
| AWS SQS (aws-sdk-sqs) | No — all manual |

There is no agent in Rust. All messaging instrumentation is manual.

## Async Context Propagation

`tokio::spawn` does not inherit the parent span context. Capture context before spawn and propagate explicitly.

**Pattern 1 — `.instrument(span)` (recommended for tracing spans):**

```rust
use tracing::Instrument;

// GOOD — capture span before spawn, attach via .instrument()
let span = tracing::info_span!("process message");
tokio::spawn(
    async move {
        do_work().await;
    }
    .instrument(span)  // propagates span context into task
);

// BAD — spawned task has no parent context
tokio::spawn(async move {
    let span = tracing::info_span!("process message");  // orphan — no parent
    do_work().await;
});
```

**Pattern 2 — `Context::current()` + `.with_context(cx)` (for raw OTel context propagation):**

```rust
use opentelemetry::Context;
use opentelemetry::trace::FutureExt;

// GOOD — capture OTel context before spawn, attach via .with_context(cx)
let cx = Context::current();
tokio::spawn(
    async move {
        // OTel context (trace_id, span_id, baggage) is available inside task
        do_work().await;
    }
    .with_context(cx)  // propagates OTel Context into task
);
```

Use `.with_context(cx)` when you need to propagate the OTel `Context` into a raw async task without creating a new tracing span (e.g., when the task itself will create spans via `tracing::info_span!` that should be children of the caller's context).

## Kafka (rdkafka)

```toml
[dependencies]
rdkafka = { version = "0.36", features = ["cmake-build"] }
```

### Producer

```rust
use opentelemetry::global;
use rdkafka::message::{Header, OwnedHeaders};
use rdkafka::producer::{FutureProducer, FutureRecord};
use std::collections::HashMap;
use tracing_opentelemetry::OpenTelemetrySpanExt;

#[tracing::instrument(skip(producer), fields(
    messaging.system = "kafka",
    messaging.destination.name = topic,
    messaging.operation = "publish",
))]
async fn publish_message(producer: &FutureProducer, topic: &str, payload: &str) {
    // Inject current span context into Kafka headers
    let cx = tracing::Span::current().context();
    let mut carrier: HashMap<String, String> = HashMap::new();
    global::get_text_map_propagator(|propagator| {
        propagator.inject_context(&cx, &mut carrier);
    });

    let headers = carrier.iter().fold(OwnedHeaders::new(), |h, (k, v)| {
        h.insert(Header { key: k, value: Some(v.as_bytes()) })
    });

    producer
        .send(
            FutureRecord::to(topic)
                .payload(payload)
                .headers(headers),
            std::time::Duration::from_secs(5),
        )
        .await
        .expect("kafka send failed");
}
```

### Consumer

```rust
use opentelemetry::global;
use rdkafka::message::Message;
use std::collections::HashMap;
use tracing_opentelemetry::OpenTelemetrySpanExt;

fn extract_kafka_context(msg: &rdkafka::message::BorrowedMessage) -> opentelemetry::Context {
    let mut carrier: HashMap<String, String> = HashMap::new();
    if let Some(headers) = msg.headers() {
        for header in headers.iter() {
            if let Some(value) = header.value {
                carrier.insert(
                    header.key.to_string(),
                    String::from_utf8_lossy(value).to_string(),
                );
            }
        }
    }
    global::get_text_map_propagator(|prop| prop.extract(&carrier))
}

async fn consume_kafka_message(msg: &rdkafka::message::BorrowedMessage<'_>) {
    let producer_ctx = extract_kafka_context(msg);

    // GOOD — new root span linked to producer; NOT a child
    let span = tracing::info_span!(
        "receive orders",
        messaging.system = "kafka",
        messaging.destination.name = msg.topic(),
        messaging.operation = "receive",
    );
    {
        use tracing_opentelemetry::OpenTelemetrySpanExt;
        let producer_span_ctx = producer_ctx.span().span_context().clone();
        if producer_span_ctx.is_valid() {
            span.add_link(producer_span_ctx);
        }
        // Do NOT: span.set_parent(producer_ctx);
    }

    async {
        process_order(msg.payload()).await;
    }
    .instrument(span)
    .await;
}
```

## AMQP (lapin)

```toml
[dependencies]
lapin = "2.3"
```

### Producer

```rust
use lapin::{options::BasicPublishOptions, BasicProperties, Channel};
use opentelemetry::global;
use std::collections::HashMap;
use tracing_opentelemetry::OpenTelemetrySpanExt;

#[tracing::instrument(skip(channel), fields(
    messaging.system = "rabbitmq",
    messaging.destination.name = routing_key,
    messaging.operation = "publish",
))]
async fn publish_amqp(channel: &Channel, exchange: &str, routing_key: &str, payload: &[u8]) {
    let cx = tracing::Span::current().context();
    let mut carrier: HashMap<String, String> = HashMap::new();
    global::get_text_map_propagator(|propagator| {
        propagator.inject_context(&cx, &mut carrier);
    });

    // Encode carrier into AMQP headers as AMQPValue strings
    let amqp_headers: lapin::types::FieldTable = carrier
        .into_iter()
        .map(|(k, v)| (k.into(), lapin::types::AMQPValue::LongString(v.into())))
        .collect::<std::collections::BTreeMap<_, _>>()
        .into();

    let props = BasicProperties::default().with_headers(amqp_headers);

    channel
        .basic_publish(exchange, routing_key, BasicPublishOptions::default(), payload, props)
        .await
        .expect("amqp publish failed")
        .await
        .expect("amqp publish confirm failed");
}
```

### Consumer

```rust
use lapin::message::Delivery;
use opentelemetry::global;
use std::collections::HashMap;
use tracing_opentelemetry::OpenTelemetrySpanExt;

fn extract_amqp_context(delivery: &Delivery) -> opentelemetry::Context {
    let mut carrier: HashMap<String, String> = HashMap::new();
    if let Some(headers) = delivery.properties.headers() {
        for (key, value) in headers.inner() {
            if let lapin::types::AMQPValue::LongString(s) = value {
                carrier.insert(key.as_str().to_string(), s.to_string());
            }
        }
    }
    global::get_text_map_propagator(|prop| prop.extract(&carrier))
}

async fn consume_amqp(delivery: &Delivery, queue_name: &str) {
    let producer_ctx = extract_amqp_context(delivery);

    // GOOD — new root span linked to producer
    let span = tracing::info_span!(
        "receive orders",
        messaging.system = "rabbitmq",
        messaging.destination.name = queue_name,
        messaging.operation = "receive",
    );
    {
        use tracing_opentelemetry::OpenTelemetrySpanExt;
        let producer_span_ctx = producer_ctx.span().span_context().clone();
        if producer_span_ctx.is_valid() {
            span.add_link(producer_span_ctx);
        }
    }

    async { process_delivery(delivery).await }
        .instrument(span)
        .await;
}
```

## AWS SQS (aws-sdk-sqs)

```toml
[dependencies]
aws-sdk-sqs = "1"
aws-config = "1"
```

### Producer

```rust
use aws_sdk_sqs::types::MessageAttributeValue;
use aws_sdk_sqs::Client;
use opentelemetry::global;
use std::collections::HashMap;
use tracing_opentelemetry::OpenTelemetrySpanExt;

#[tracing::instrument(skip(sqs_client), fields(
    messaging.system = "aws_sqs",
    messaging.destination.name = queue_url,
    messaging.operation = "publish",
))]
async fn send_sqs_message(sqs_client: &Client, queue_url: &str, body: &str) {
    let cx = tracing::Span::current().context();
    let mut carrier: HashMap<String, String> = HashMap::new();
    global::get_text_map_propagator(|propagator| {
        propagator.inject_context(&cx, &mut carrier);
    });

    let message_attrs: HashMap<String, MessageAttributeValue> = carrier
        .into_iter()
        .map(|(k, v)| {
            (
                k,
                MessageAttributeValue::builder()
                    .data_type("String")
                    .string_value(v)
                    .build()
                    .unwrap(),
            )
        })
        .collect();

    sqs_client
        .send_message()
        .queue_url(queue_url)
        .message_body(body)
        .set_message_attributes(Some(message_attrs))
        .send()
        .await
        .expect("sqs send failed");
}
```

### Consumer

```rust
use aws_sdk_sqs::types::Message;
use opentelemetry::global;
use std::collections::HashMap;
use tracing_opentelemetry::OpenTelemetrySpanExt;

fn extract_sqs_context(msg: &Message) -> opentelemetry::Context {
    let mut carrier: HashMap<String, String> = HashMap::new();
    if let Some(attrs) = msg.message_attributes() {
        for (k, v) in attrs {
            if let Some(s) = v.string_value() {
                carrier.insert(k.clone(), s.to_string());
            }
        }
    }
    global::get_text_map_propagator(|prop| prop.extract(&carrier))
}

async fn consume_sqs_message(msg: &Message, queue_name: &str) {
    let producer_ctx = extract_sqs_context(msg);

    // GOOD — new root span linked to producer
    let span = tracing::info_span!(
        "receive orders",
        messaging.system = "aws_sqs",
        messaging.destination.name = queue_name,
        messaging.operation = "receive",
    );
    {
        use tracing_opentelemetry::OpenTelemetrySpanExt;
        let producer_span_ctx = producer_ctx.span().span_context().clone();
        if producer_span_ctx.is_valid() {
            span.add_link(producer_span_ctx);
        }
    }

    async { process_sqs(msg).await }.instrument(span).await;
}
```

## Verification

```bash
# Check producer spans
tsuga spans search --query "context.service.name:<producer-service> messaging.system:kafka" --max-results 5

# Check consumer spans and Links field
tsuga spans search --query "context.service.name:<consumer-service> messaging.operation:receive" --max-results 5
```
