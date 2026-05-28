# Async Messaging — Go OTel SDK

> **Last verified:** 2026-03-23 | SDK v1.42.0

This file covers distributed trace propagation across Kafka, SQS, and RabbitMQ in Go. For context propagation in synchronous HTTP/gRPC see `references/propagation.md`.

---

## Context Model Decision

### Use span Links (recommended for most queue patterns)

CONSUMER spans MUST use `trace.WithLinks(...)` with the extracted producer span context — NOT parent-child.

**Why:** A consumer job often executes inside an unrelated ambient context (e.g., inside an HTTP server handler). Making the consumer a child of the producer creates false trace topology and misleads latency analysis.

```
BAD:  producer span → consumer span (parent-child)
       ^ creates one merged trace; consumer latency appears inside producer trace

GOOD: producer span
      consumer span → [link] → producer span
       ^ separate traces; navigable back to producer via link
```

**Use parent-child only when:**
- The consumer is a direct extension of the same request (synchronous hand-off through a queue)
- The SLA of producer + consumer is measured as a single unit

### Span naming

Pattern: `{operation} {destination}` — e.g., `"publish shop.orders"`, `"process invoice.created"`

| BAD | GOOD |
|---|---|
| `kafka.publish` | `publish shop.orders` |
| `consume` | `process invoice.created` |
| `sqs_send` | `publish payment.events` |

---

## Required Semantic Convention Attributes

Set these on all messaging spans:

| Attribute | Value |
|---|---|
| `messaging.system` | `kafka` / `aws_sqs` / `rabbitmq` |
| `messaging.destination.name` | topic or queue name |
| `messaging.operation.type` | `publish` (producer) / `process` (consumer) |
| `messaging.operation.name` | `publish` / `receive` / `process` |
| `messaging.message.id` | message ID if available |

---

## Kafka

Go has no official OTel auto-instrumentation for Kafka. Use manual patterns below.

### Producer — inject trace context into message headers

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/attribute"
    "go.opentelemetry.io/otel/codes"
    "go.opentelemetry.io/otel/propagation"
    oteltrace "go.opentelemetry.io/otel/trace"
)

tracer := otel.Tracer("my-service")

func publishOrder(ctx context.Context, topic string, order Order) error {
    ctx, span := tracer.Start(ctx, "publish "+topic,
        oteltrace.WithSpanKind(oteltrace.SpanKindProducer),
        oteltrace.WithAttributes(
            attribute.String("messaging.system", "kafka"),
            attribute.String("messaging.destination.name", topic),
            attribute.String("messaging.operation.type", "publish"),
            attribute.String("messaging.operation.name", "publish"),
        ),
    )
    defer span.End()

    // Inject trace context into Kafka message headers
    headers := make(propagation.MapCarrier)
    otel.GetTextMapPropagator().Inject(ctx, headers)

    msg := &sarama.ProducerMessage{
        Topic: topic,
        Value: sarama.StringEncoder(encodeOrder(order)),
    }
    for k, v := range headers {
        msg.Headers = append(msg.Headers, sarama.RecordHeader{
            Key:   []byte(k),
            Value: []byte(v),
        })
    }
    _, _, err := producer.SendMessage(msg)
    return err
}
```

### Consumer — extract trace context, start root span with Link

```go
func processMessage(msg *sarama.ConsumerMessage) {
    // Extract context from message headers
    carrier := make(propagation.MapCarrier)
    for _, h := range msg.Headers {
        carrier[string(h.Key)] = string(h.Value)
    }
    remoteCtx := otel.GetTextMapPropagator().Extract(context.Background(), carrier)

    // Start a new ROOT span (not a child!) with a Link to the producer span
    ctx, span := tracer.Start(context.Background(), "process "+msg.Topic,
        oteltrace.WithSpanKind(oteltrace.SpanKindConsumer),
        oteltrace.WithLinks(oteltrace.Link{
            SpanContext: oteltrace.SpanContextFromContext(remoteCtx),
        }),
        oteltrace.WithAttributes(
            attribute.String("messaging.system", "kafka"),
            attribute.String("messaging.destination.name", msg.Topic),
            attribute.String("messaging.operation.type", "process"),
            attribute.String("messaging.operation.name", "process"),
        ),
    )
    defer span.End()

    // Pass ctx through all downstream work
    if err := handleMessage(ctx, msg); err != nil {
        span.RecordError(err)
        span.SetStatus(codes.Error, "message processing failed")
    }
}
```

> **otelsarama contrib (deprecated):** `go.opentelemetry.io/contrib/instrumentation/github.com/Shopify/sarama/otelsarama` is deprecated and no longer maintained — `github.com/Shopify/sarama` moved to `github.com/IBM/sarama`. For IBM/sarama instrumentation, use the community fork `github.com/dnwe/otelsarama`. The manual inject/extract patterns above work with any sarama fork.

---

## SQS

SQS carries trace context in **message attributes** (not message body — body is reserved for application data).

### Producer — inject into MessageAttributes

```go
import (
    "github.com/aws/aws-sdk-go-v2/service/sqs"
    "github.com/aws/aws-sdk-go-v2/service/sqs/types"
    "go.opentelemetry.io/otel/propagation"
)

func sendSQSMessage(ctx context.Context, queueURL, body string) error {
    ctx, span := tracer.Start(ctx, "publish "+queueName,
        oteltrace.WithSpanKind(oteltrace.SpanKindProducer),
        oteltrace.WithAttributes(
            attribute.String("messaging.system", "aws_sqs"),
            attribute.String("messaging.destination.name", queueName),
            attribute.String("messaging.operation.type", "publish"),
        ),
    )
    defer span.End()

    carrier := make(propagation.MapCarrier)
    otel.GetTextMapPropagator().Inject(ctx, carrier)

    msgAttrs := map[string]types.MessageAttributeValue{}
    for k, v := range carrier {
        msgAttrs[k] = types.MessageAttributeValue{
            DataType:    aws.String("String"),
            StringValue: aws.String(v),
        }
    }

    _, err := sqsClient.SendMessage(ctx, &sqs.SendMessageInput{
        QueueUrl:          &queueURL,
        MessageBody:       &body,
        MessageAttributes: msgAttrs,
    })
    return err
}
```

### Consumer — extract from MessageAttributes

```go
for _, msg := range result.Messages {
    carrier := make(propagation.MapCarrier)
    for k, v := range msg.MessageAttributes {
        if v.StringValue != nil {
            carrier[k] = *v.StringValue
        }
    }
    remoteCtx := otel.GetTextMapPropagator().Extract(context.Background(), carrier)

    ctx, span := tracer.Start(context.Background(), "process "+queueName,
        oteltrace.WithSpanKind(oteltrace.SpanKindConsumer),
        oteltrace.WithLinks(oteltrace.Link{
            SpanContext: oteltrace.SpanContextFromContext(remoteCtx),
        }),
        oteltrace.WithAttributes(
            attribute.String("messaging.system", "aws_sqs"),
            attribute.String("messaging.destination.name", queueName),
            attribute.String("messaging.operation.type", "process"),
            attribute.String("messaging.operation.name", "process"),
        ),
    )
    defer span.End()
    processMessage(ctx, msg)
}
```

> **otelaws contrib:** `go.opentelemetry.io/contrib/instrumentation/github.com/aws/aws-sdk-go-v2/otelaws` can auto-instrument SQS send calls if using AWS SDK v2.

---

## RabbitMQ

RabbitMQ carries trace context in **AMQP message headers**.

### Producer — inject into AMQP headers

```go
import (
    amqp "github.com/rabbitmq/amqp091-go"
    "go.opentelemetry.io/otel/propagation"
)

func publishRabbitMQ(ctx context.Context, exchange, routingKey string, body []byte) error {
    ctx, span := tracer.Start(ctx, "publish "+routingKey,
        oteltrace.WithSpanKind(oteltrace.SpanKindProducer),
        oteltrace.WithAttributes(
            attribute.String("messaging.system", "rabbitmq"),
            attribute.String("messaging.destination.name", routingKey),
            attribute.String("messaging.operation.type", "publish"),
        ),
    )
    defer span.End()

    headers := amqp.Table{}
    carrier := propagation.MapCarrier{}
    otel.GetTextMapPropagator().Inject(ctx, carrier)
    for k, v := range carrier {
        headers[k] = v
    }

    return ch.PublishWithContext(ctx, exchange, routingKey, false, false,
        amqp.Publishing{
            ContentType: "application/json",
            Body:        body,
            Headers:     headers,
        },
    )
}
```

### Consumer — extract from AMQP headers

```go
msgs, _ := ch.Consume(queue, "", false, false, false, false, nil)
for msg := range msgs {
    carrier := propagation.MapCarrier{}
    for k, v := range msg.Headers {
        if s, ok := v.(string); ok {
            carrier[k] = s
        }
    }
    remoteCtx := otel.GetTextMapPropagator().Extract(context.Background(), carrier)

    ctx, span := tracer.Start(context.Background(), "process "+queue,
        oteltrace.WithSpanKind(oteltrace.SpanKindConsumer),
        oteltrace.WithLinks(oteltrace.Link{
            SpanContext: oteltrace.SpanContextFromContext(remoteCtx),
        }),
        oteltrace.WithAttributes(
            attribute.String("messaging.system", "rabbitmq"),
            attribute.String("messaging.destination.name", queue),
            attribute.String("messaging.operation.type", "process"),
        ),
    )
    processDelivery(ctx, msg)
    span.End()
    msg.Ack(false)
}
```

---

## Verification

```bash
# Check consumer spans have links[] populated
tsuga spans search --query "context.service.name:<consumer-service>" --max-results 5
# Inspect: spans should show links[] array pointing to producer trace IDs

# Check producer spans
tsuga spans search --query "context.service.name:<producer-service> messaging.system:kafka" --max-results 5
```

If context is still not propagating after implementing → `tsuga-debug-missing-trace-propagation`
