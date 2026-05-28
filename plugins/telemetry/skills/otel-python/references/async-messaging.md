# Async Messaging Instrumentation — Python OTel

> **Last verified:** 2026-03-23 | SDK: `opentelemetry-api` 1.40.0

Covers Kafka, SQS, Celery, and RabbitMQ. For HTTP/gRPC propagation see `references/propagation.md`.

---

## Context model: use span Links, not parent-child

CONSUMER spans MUST use `links=[trace.Link(parent_span_ctx)]`, NOT `context=parent_ctx`.

**Why:** A message consumer starts a new unit of work. Making the consumer span a child of the producer span merges unrelated traces and distorts latency data for both sides.

```python
# BAD — consumer span is child of producer trace
with tracer.start_as_current_span("process order", context=parent_ctx) as span:
    ...

# GOOD — new root span, linked to producer trace
parent_span_ctx = trace.get_current_span(parent_ctx).get_span_context()
with tracer.start_as_current_span(
    "process order",
    links=[trace.Link(parent_span_ctx)] if parent_span_ctx.is_valid else [],
) as span:
    ...
```

---

## Span naming

Pattern: `{operation} {destination}` — lowercase, space-separated.

| BAD | GOOD |
|-----|------|
| `kafkaConsumer` | `process shop.orders` |
| `sendMessage` | `publish invoice.created` |
| `SQS-receive` | `receive payment-events` |
| `celery_task_run` | `process send-welcome-email` |

---

## Required `messaging.*` semconv attributes

| Attribute | Required | Example |
|-----------|----------|---------|
| `messaging.system` | Yes | `"kafka"`, `"aws_sqs"`, `"rabbitmq"`, `"redis"` |
| `messaging.destination.name` | Yes | `"shop.orders"`, `"payment-events"` |
| `messaging.operation` | Yes | `"publish"`, `"process"`, `"receive"` |
| `messaging.message.id` | Recommended | message UUID |
| `messaging.kafka.partition` | Kafka | partition number |
| `messaging.kafka.consumer.group` | Kafka consumer | consumer group name |

---

## Auto-instrumentation availability

| Library | Auto-instrumentation package | Notes |
|---------|------------------------------|-------|
| kafka-python | `opentelemetry-instrumentation-kafka-python` | Handles inject/extract automatically |
| confluent-kafka | No official package | Use manual patterns below |
| aiokafka | `opentelemetry-instrumentation-aiokafka` | — |
| boto3/botocore (SQS) | `opentelemetry-instrumentation-botocore` | Via `otelaws` decorator |
| Celery | `opentelemetry-instrumentation-celery` | Auto-instruments task dispatch and execution |
| pika (RabbitMQ) | `opentelemetry-instrumentation-pika` | — |

If auto-instrumentation is available and installed via `opentelemetry-bootstrap -a install`, prefer it. Use manual patterns below when auto-instrumentation is not available or needs extension.

---

## Kafka (confluent-kafka / aiokafka)

### Producer — inject into message headers

```python
from opentelemetry import propagate, trace
from opentelemetry.trace import SpanKind
from confluent_kafka import Producer

tracer = trace.get_tracer("my-service")

def publish_order(producer: Producer, topic: str, order_id: str, payload: bytes):
    carrier = {}
    propagate.inject(carrier)
    # Kafka headers are list of (key, value) tuples; values must be bytes
    headers = [(k, v.encode()) for k, v in carrier.items()]

    with tracer.start_as_current_span(
        f"publish {topic}",
        kind=SpanKind.PRODUCER,
        attributes={
            "messaging.system": "kafka",
            "messaging.destination.name": topic,
            "messaging.operation": "publish",
        },
    ) as span:
        producer.produce(topic, value=payload, headers=headers)
    # flush() outside the span — it blocks for delivery ack and would inflate
    # PRODUCER span duration with network round-trip time
    producer.flush()
```

### Consumer — extract and start new root span with Link

```python
from opentelemetry import propagate, trace
from opentelemetry.trace import SpanKind
from confluent_kafka import Consumer

tracer = trace.get_tracer("my-service")

def process_messages(consumer: Consumer):
    msg = consumer.poll(1.0)
    if msg is None:
        return

    # Extract producer's context from headers
    headers = {k: v.decode() for k, v in (msg.headers() or [])}
    parent_ctx = propagate.extract(headers)

    # Get the SpanContext to use as a Link (do not use as parent)
    parent_span_ctx = trace.get_current_span(parent_ctx).get_span_context()

    with tracer.start_as_current_span(
        f"process {msg.topic()}",
        kind=SpanKind.CONSUMER,
        links=[trace.Link(parent_span_ctx)] if parent_span_ctx.is_valid else [],
        attributes={
            "messaging.system": "kafka",
            "messaging.destination.name": msg.topic(),
            "messaging.operation": "process",
            "messaging.kafka.partition": msg.partition(),
        },
    ) as span:
        handle_message(msg.value())
```

---

## SQS

**Recommended:** use `opentelemetry-instrumentation-botocore` — it auto-instruments all boto3/botocore calls including SQS.

**Manual pattern:**

```python
import boto3
from opentelemetry import propagate, trace
from opentelemetry.trace import SpanKind

tracer = trace.get_tracer("my-service")
sqs = boto3.client("sqs")

def send_sqs_message(queue_url: str, body: str, queue_name: str):
    with tracer.start_as_current_span(
        f"publish {queue_name}",
        kind=SpanKind.PRODUCER,
        attributes={
            "messaging.system": "aws_sqs",
            "messaging.destination.name": queue_name,
            "messaging.operation": "publish",
        },
    ):
        carrier = {}
        propagate.inject(carrier)

        message_attributes = {
            k: {"DataType": "String", "StringValue": v}
            for k, v in carrier.items()
        }
        sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=body,
            MessageAttributes=message_attributes,
        )

def receive_and_process(queue_url: str, queue_name: str):
    response = sqs.receive_message(
        QueueUrl=queue_url,
        MessageAttributeNames=["All"],
    )
    for msg in response.get("Messages", []):
        carrier = {
            k: v["StringValue"]
            for k, v in msg.get("MessageAttributes", {}).items()
        }
        parent_ctx = propagate.extract(carrier)
        parent_span_ctx = trace.get_current_span(parent_ctx).get_span_context()

        with tracer.start_as_current_span(
            f"process {queue_name}",
            kind=SpanKind.CONSUMER,
            links=[trace.Link(parent_span_ctx)] if parent_span_ctx.is_valid else [],
            attributes={
                "messaging.system": "aws_sqs",
                "messaging.destination.name": queue_name,
                "messaging.operation": "process",
                "messaging.message.id": msg["MessageId"],
            },
        ):
            process_message(msg["Body"])
```

---

## Celery

**Recommended:** `opentelemetry-instrumentation-celery` auto-instruments task dispatch and worker execution. Install via `opentelemetry-bootstrap -a install`.

**Manual pattern** (when auto-instrumentation is not available):

The `otel_headers` kwargs pattern injects propagation headers into task arguments at dispatch time, then extracts them inside the worker.

> **`messaging.system` note:** Celery is a task framework, not a messaging system. Use the underlying broker's system identifier: `"redis"` (Redis broker), `"rabbitmq"` (RabbitMQ broker), or `"aws_sqs"` (SQS broker). `"celery"` is not a valid semconv value.

```python
from celery import Celery
from opentelemetry import propagate, trace
from opentelemetry.trace import SpanKind

app = Celery("tasks")  # configured with Redis broker in this example
tracer = trace.get_tracer("my-service")

CELERY_BROKER_SYSTEM = "redis"  # match your actual broker: "redis", "rabbitmq", "aws_sqs"
CELERY_QUEUE = "orders"         # the queue name tasks are routed to

@app.task
def process_order(order_id: str, otel_headers: dict = None):
    parent_ctx = propagate.extract(otel_headers or {})
    parent_span_ctx = trace.get_current_span(parent_ctx).get_span_context()

    with tracer.start_as_current_span(
        f"process {CELERY_QUEUE}",
        kind=SpanKind.CONSUMER,
        links=[trace.Link(parent_span_ctx)] if parent_span_ctx.is_valid else [],
        attributes={
            "messaging.system": CELERY_BROKER_SYSTEM,
            "messaging.destination.name": CELERY_QUEUE,
            "messaging.operation": "process",
        },
    ) as span:
        span.set_attribute("order.id", order_id)
        do_processing(order_id)

# Caller — inject before dispatching
def dispatch_order(order_id: str):
    with tracer.start_as_current_span(
        f"publish {CELERY_QUEUE}",
        kind=SpanKind.PRODUCER,
        attributes={
            "messaging.system": CELERY_BROKER_SYSTEM,
            "messaging.destination.name": CELERY_QUEUE,
            "messaging.operation": "publish",
        },
    ):
        headers = {}
        propagate.inject(headers)
        process_order.delay(order_id, otel_headers=headers)
```

---

## RabbitMQ (pika)

**Recommended:** `opentelemetry-instrumentation-pika` auto-instruments pika connections.

**Manual pattern:**

```python
import pika
from opentelemetry import propagate, trace
from opentelemetry.trace import SpanKind

tracer = trace.get_tracer("my-service")

def publish_message(channel, exchange: str, routing_key: str, body: bytes):
    with tracer.start_as_current_span(
        f"publish {exchange}",
        kind=SpanKind.PRODUCER,
        attributes={
            "messaging.system": "rabbitmq",
            "messaging.destination.name": exchange,
            "messaging.operation": "publish",
        },
    ):
        carrier = {}
        propagate.inject(carrier)

        headers = {k: v for k, v in carrier.items()}
        properties = pika.BasicProperties(headers=headers)
        channel.basic_publish(
            exchange=exchange,
            routing_key=routing_key,
            body=body,
            properties=properties,
        )

def consume_message(channel, method, properties, body):
    carrier = dict(properties.headers or {})
    parent_ctx = propagate.extract(carrier)
    parent_span_ctx = trace.get_current_span(parent_ctx).get_span_context()

    with tracer.start_as_current_span(
        f"process {method.routing_key}",
        kind=SpanKind.CONSUMER,
        links=[trace.Link(parent_span_ctx)] if parent_span_ctx.is_valid else [],
        attributes={
            "messaging.system": "rabbitmq",
            "messaging.destination.name": method.routing_key,
            "messaging.operation": "process",
        },
    ):
        handle_message(body)
```

---

## Verification

```bash
# Confirm producer spans appear
tsuga spans search --query "context.service.name:my-service messaging.operation:publish" --max-results 5

# Confirm consumer spans appear with links
tsuga spans search --query "context.service.name:my-service messaging.operation:process" --max-results 5

# Check that consumer spans are root spans (no parentSpanId)
# and have links to producer spans
```
