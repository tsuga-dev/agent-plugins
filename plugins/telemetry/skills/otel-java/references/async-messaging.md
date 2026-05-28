# Async Messaging — Java OTel

> **Last verified:** 2026-03-23 | SDK: `opentelemetry-bom` 1.60.1 | Agent: `opentelemetry-javaagent` 2.26.0

## Context Model: Use span Links, Not Parent-Child

Async CONSUMER spans must use **span Links** to the producer span — not parent-child relationships. The producer and consumer are separate operations in separate traces.

```java
// BAD — makes consumer appear as a child of the producer HTTP request
Span span = tracer.spanBuilder("kafka.process")
    .setParent(extractedProducerContext)
    .startSpan();

// GOOD — new root span linked to producer for cross-trace navigation
Span span = tracer.spanBuilder("receive orders")
    .setNoParent()
    .addLink(Span.fromContext(extractedProducerContext).getSpanContext())
    .setSpanKind(SpanKind.CONSUMER)
    .startSpan();
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
| `messaging.system` | Yes | `kafka`, `activemq`, `aws_sqs`, `rabbitmq` |
| `messaging.destination.name` | Yes | `orders`, `user-events` |
| `messaging.operation.type` | Yes | `send`, `receive`, `process` |
| `messaging.message.id` | Recommended | `"msg-abc-123"` |

> Check `otel-semantic-conventions` for the full `messaging.*` namespace before adding custom attributes.

## Auto-Instrumentation Coverage (Java Agent v2.26.0)

| System | Auto-instrumented by agent? |
|--------|-----------------------------|
| Kafka | Yes — producer inject + consumer extract with Link |
| JMS / ActiveMQ | Yes |
| RabbitMQ | Yes |
| AWS SQS (via AWS SDK v2) | Yes — via `opentelemetry-aws-sdk-2.2` extension |

For agent-covered systems, manual propagation code is only needed for custom transports or non-standard usage patterns.

## Kafka — Manual Propagation

### Producer

```java
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.context.Context;
import org.apache.kafka.clients.producer.ProducerRecord;
import java.nio.charset.StandardCharsets;

ProducerRecord<String, String> record = new ProducerRecord<>("orders", key, value);

// Inject trace context into Kafka message headers
GlobalOpenTelemetry.getPropagators()
    .getTextMapPropagator()
    .inject(Context.current(), record.headers(),
        (carrier, k, v) -> carrier.add(k, v.getBytes(StandardCharsets.UTF_8)));

producer.send(record);
```

### Consumer

```java
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.Scope;
import io.opentelemetry.context.propagation.TextMapGetter;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.common.header.Header;
import org.apache.kafka.common.header.Headers;
import java.util.ArrayList;
import java.util.List;
import java.nio.charset.StandardCharsets;

ConsumerRecord<String, String> record = ...; // from poll()

// Extract producer context
Context producerContext = GlobalOpenTelemetry.getPropagators()
    .getTextMapPropagator()
    .extract(Context.current(), record.headers(),
        new TextMapGetter<>() {
            @Override
            public Iterable<String> keys(Headers carrier) {
                List<String> keys = new ArrayList<>();
                carrier.forEach(h -> keys.add(h.key()));
                return keys;
            }
            @Override
            public String get(Headers carrier, String key) {
                Header header = carrier.lastHeader(key);
                return header == null ? null
                    : new String(header.value(), StandardCharsets.UTF_8);
            }
        });

// GOOD — new root linked to producer; do NOT set parent
Span span = tracer.spanBuilder("receive " + record.topic())
    .setNoParent()
    .addLink(Span.fromContext(producerContext).getSpanContext())
    .setSpanKind(SpanKind.CONSUMER)
    .setAttribute("messaging.system", "kafka")
    .setAttribute("messaging.destination.name", record.topic())
    .setAttribute("messaging.operation.type", "receive")
    .startSpan();

try (Scope scope = span.makeCurrent()) {
    processRecord(record);
} catch (Exception e) {
    span.recordException(e);
    span.setStatus(StatusCode.ERROR, "kafka processing failed");
    throw e;
} finally {
    span.end();
}
```

## JMS / ActiveMQ — Manual Propagation

JMS property names cannot contain hyphens — replace `-` with `_` when storing `traceparent`, and reverse on extraction.

### Producer

```java
import io.opentelemetry.context.propagation.TextMapSetter;
import javax.jms.Message;
import javax.jms.JMSException;

TextMapSetter<Message> setter = (message, key, value) -> {
    try {
        message.setStringProperty(key.replace("-", "_"), value);
    } catch (JMSException e) {
        throw new RuntimeException(e);
    }
};

GlobalOpenTelemetry.getPropagators()
    .getTextMapPropagator()
    .inject(Context.current(), message, setter);

producer.send(destination, message);
```

### Consumer

```java
import io.opentelemetry.context.propagation.TextMapGetter;
import javax.jms.Message;
import javax.jms.JMSException;
import java.util.Collections;

TextMapGetter<Message> getter = new TextMapGetter<>() {
    @Override
    public Iterable<String> keys(Message carrier) {
        try {
            return Collections.list(carrier.getPropertyNames());
        } catch (JMSException e) {
            return Collections.emptyList();
        }
    }
    @Override
    public String get(Message carrier, String key) {
        try {
            // Reverse hyphen → underscore substitution from producer
            return carrier.getStringProperty(key.replace("-", "_"));
        } catch (JMSException e) {
            return null;
        }
    }
};

Context producerContext = GlobalOpenTelemetry.getPropagators()
    .getTextMapPropagator()
    .extract(Context.current(), message, getter);

Span span = tracer.spanBuilder("receive " + destinationName)
    .setNoParent()
    .addLink(Span.fromContext(producerContext).getSpanContext())
    .setSpanKind(SpanKind.CONSUMER)
    .setAttribute("messaging.system", "activemq")
    .setAttribute("messaging.destination.name", destinationName)
    .setAttribute("messaging.operation.type", "receive")
    .startSpan();
try (Scope scope = span.makeCurrent()) {
    processMessage(message);
} finally {
    span.end();
}
```

## AWS SQS

Auto-instrumented via `opentelemetry-aws-sdk-2.2` extension when using the Java agent or the AWS SDK v2 instrumentation library. Manual pattern for custom setups:

### Producer (inject into MessageAttribute)

```java
import software.amazon.awssdk.services.sqs.model.MessageAttributeValue;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;
import java.util.HashMap;
import java.util.Map;

Map<String, MessageAttributeValue> attrs = new HashMap<>();
GlobalOpenTelemetry.getPropagators()
    .getTextMapPropagator()
    .inject(Context.current(), attrs,
        (carrier, key, value) -> carrier.put(key,
            MessageAttributeValue.builder()
                .dataType("String")
                .stringValue(value)
                .build()));

SendMessageRequest request = SendMessageRequest.builder()
    .queueUrl(queueUrl)
    .messageBody(body)
    .messageAttributes(attrs)
    .build();
sqsClient.sendMessage(request);
```

### Consumer (extract from MessageAttribute)

```java
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.context.Scope;
import software.amazon.awssdk.services.sqs.model.Message;
import software.amazon.awssdk.services.sqs.model.MessageAttributeValue;
import java.util.Map;

Message sqsMessage = ...; // from receiveMessage()

Context producerContext = GlobalOpenTelemetry.getPropagators()
    .getTextMapPropagator()
    .extract(Context.current(), sqsMessage.messageAttributes(),
        new TextMapGetter<>() {
            @Override
            public Iterable<String> keys(Map<String, MessageAttributeValue> carrier) {
                return carrier.keySet();
            }
            @Override
            public String get(Map<String, MessageAttributeValue> carrier, String key) {
                MessageAttributeValue val = carrier.get(key);
                return val == null ? null : val.stringValue();
            }
        });

// GOOD — new root linked to producer; do NOT set parent
Span span = tracer.spanBuilder("receive " + queueName)
    .setNoParent()
    .addLink(Span.fromContext(producerContext).getSpanContext())
    .setSpanKind(SpanKind.CONSUMER)
    .setAttribute("messaging.system", "aws_sqs")
    .setAttribute("messaging.destination.name", queueName)
    .setAttribute("messaging.operation.type", "receive")
    .startSpan();
try (Scope scope = span.makeCurrent()) {
    processMessage(sqsMessage);
} finally {
    span.end();
}
```

## RabbitMQ

Auto-instrumented by the Java agent via AMQP instrumentation. For manual propagation, inject/extract from AMQP message headers (string-valued map).

### Producer

```java
// Inject into AMQP BasicProperties headers
Map<String, Object> headers = new HashMap<>();
GlobalOpenTelemetry.getPropagators()
    .getTextMapPropagator()
    .inject(Context.current(), headers,
        (carrier, key, value) -> carrier.put(key, value));

AMQP.BasicProperties props = new AMQP.BasicProperties.Builder()
    .headers(headers)
    .build();
channel.basicPublish(exchange, routingKey, props, body);
```

### Consumer

```java
import com.rabbitmq.client.Delivery;
import io.opentelemetry.context.propagation.TextMapGetter;
import java.util.Map;

Delivery delivery = ...; // from consumer callback
Map<String, Object> amqpHeaders = delivery.getProperties().getHeaders();

Context producerContext = GlobalOpenTelemetry.getPropagators()
    .getTextMapPropagator()
    .extract(Context.current(), amqpHeaders,
        new TextMapGetter<>() {
            @Override
            public Iterable<String> keys(Map<String, Object> carrier) {
                return carrier.keySet();
            }
            @Override
            public String get(Map<String, Object> carrier, String key) {
                Object val = carrier.get(key);
                return val == null ? null : val.toString();
            }
        });

// GOOD — new root linked to producer
Span span = tracer.spanBuilder("receive " + queueName)
    .setNoParent()
    .addLink(Span.fromContext(producerContext).getSpanContext())
    .setSpanKind(SpanKind.CONSUMER)
    .setAttribute("messaging.system", "rabbitmq")
    .setAttribute("messaging.destination.name", queueName)
    .setAttribute("messaging.operation.type", "receive")
    .startSpan();
try (Scope scope = span.makeCurrent()) {
    processDelivery(delivery);
} finally {
    span.end();
}
```

## Verification

```bash
# Check producer spans
tsuga spans search --query "context.service.name:<producer-service> messaging.system:kafka" --max-results 5

# Check consumer spans and Links field
tsuga spans search --query "context.service.name:<consumer-service> messaging.operation.type:receive" --max-results 5
```
