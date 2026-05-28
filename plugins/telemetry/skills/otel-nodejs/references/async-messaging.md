# Async Messaging — Node.js OTel

> **Last verified:** 2026-03-23 | SDK: `@opentelemetry/sdk-node` 0.213.x / `@opentelemetry/api` 1.9.x

## Context Model: Use span Links, Not Parent-Child

Async CONSUMER spans must use **span Links** to the producer span — not parent-child relationships. The producer and consumer are separate operations in separate traces.

```javascript
const { trace, SpanKind, context, propagation } = require('@opentelemetry/api');

// BAD — makes consumer appear as a child of the producer HTTP request
tracer.startActiveSpan('process message', {}, extractedProducerContext, (span) => {
  doProcessing();
  span.end();
});

// GOOD — new root span linked to producer for cross-trace navigation
const producerSpanContext = trace.getSpanContext(extractedProducerContext);
tracer.startActiveSpan(
  'receive orders',
  {
    kind: SpanKind.CONSUMER,
    links: [{ context: producerSpanContext }],
  },
  context.active(),  // start from current active context, NOT extractedProducerContext
  (span) => {
    span.setAttribute('messaging.system', 'kafka');
    span.setAttribute('messaging.destination.name', 'orders');
    span.setAttribute('messaging.operation', 'receive');
    doProcessing();
    span.end();
  }
);
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

| System | Package | Auto-instrumented? |
|--------|---------|--------------------|
| Kafka (kafkajs) | `@opentelemetry/instrumentation-kafkajs` | Yes — producer inject + consumer extract with Link |
| AMQP (amqplib) | `@opentelemetry/instrumentation-amqplib` | Yes |
| AWS SQS (aws-sdk v3) | `@opentelemetry/instrumentation-aws-sdk` | Yes — via aws-sdk instrumentation |
| AWS SQS (aws-sdk v2) | `@opentelemetry/instrumentation-aws-sdk` | Yes |

For auto-instrumented systems, manual propagation code is only needed for custom transports or non-standard usage patterns.

## Kafka (kafkajs) — Manual Propagation

KafkaJS headers are `Buffer` values. Convert to `Buffer.from(value)` on inject; convert back with `.toString()` on extract.

### Producer

```javascript
const { propagation, context } = require('@opentelemetry/api');

async function sendMessage(producer, topic, value) {
  const carrier = {};
  propagation.inject(context.active(), carrier);

  // Convert string header values to Buffer for Kafka wire protocol
  const headers = Object.entries(carrier).reduce((acc, [k, v]) => {
    acc[k] = Buffer.from(v);
    return acc;
  }, {});

  await producer.send({
    topic,
    messages: [{ value: JSON.stringify(value), headers }],
  });
}
```

### Consumer

```javascript
const { propagation, context, trace, SpanKind } = require('@opentelemetry/api');
const tracer = trace.getTracer('my-service');

async function processMessage(message) {
  // Convert Buffer headers back to strings for extraction
  const carrier = Object.entries(message.headers || {}).reduce((acc, [k, v]) => {
    acc[k] = Buffer.isBuffer(v) ? v.toString() : v;
    return acc;
  }, {});

  const producerContext = propagation.extract(context.active(), carrier);
  const producerSpanContext = trace.getSpanContext(producerContext);

  // GOOD — new root span with Link to producer; NOT a child
  tracer.startActiveSpan(
    'receive ' + message.topic,
    {
      kind: SpanKind.CONSUMER,
      links: producerSpanContext ? [{ context: producerSpanContext }] : [],
    },
    context.active(),   // do NOT pass producerContext as the context argument
    async (span) => {
      try {
        span.setAttribute('messaging.system', 'kafka');
        span.setAttribute('messaging.destination.name', message.topic);
        span.setAttribute('messaging.operation', 'receive');
        await doProcessing(message);
        span.end();
      } catch (err) {
        span.recordException(err);
        span.setStatus({ code: require('@opentelemetry/api').SpanStatusCode.ERROR, message: err.message });
        span.end();
        throw err;
      }
    }
  );
}
```

## AMQP (amqplib) — Manual Propagation

### Producer

```javascript
const { propagation, context } = require('@opentelemetry/api');

async function publishMessage(channel, exchange, routingKey, body) {
  const carrier = {};
  propagation.inject(context.active(), carrier);

  // AMQP headers are a plain string-keyed object
  channel.publish(exchange, routingKey, Buffer.from(JSON.stringify(body)), {
    headers: carrier,
  });
}
```

### Consumer

```javascript
const { propagation, context, trace, SpanKind } = require('@opentelemetry/api');

channel.consume(queue, (msg) => {
  if (!msg) return;

  const carrier = msg.properties.headers || {};
  const producerContext = propagation.extract(context.active(), carrier);
  const producerSpanContext = trace.getSpanContext(producerContext);

  // GOOD — new root span linked to producer
  tracer.startActiveSpan(
    'receive ' + queue,
    {
      kind: SpanKind.CONSUMER,
      links: producerSpanContext ? [{ context: producerSpanContext }] : [],
    },
    context.active(),
    (span) => {
      try {
        span.setAttribute('messaging.system', 'rabbitmq');
        span.setAttribute('messaging.destination.name', queue);
        span.setAttribute('messaging.operation', 'receive');
        processMessage(msg);
        channel.ack(msg);
        span.end();
      } catch (err) {
        span.recordException(err);
        span.setStatus({ code: require('@opentelemetry/api').SpanStatusCode.ERROR, message: err.message });
        channel.nack(msg);
        span.end();
      }
    }
  );
});
```

## AWS SQS (`@aws-sdk/client-sqs`) — Manual Propagation

### Producer (inject into MessageAttribute)

```javascript
const { propagation, context } = require('@opentelemetry/api');
const { SQSClient, SendMessageCommand } = require('@aws-sdk/client-sqs');

async function sendSqsMessage(queueUrl, body) {
  const carrier = {};
  propagation.inject(context.active(), carrier);

  const messageAttributes = Object.entries(carrier).reduce((acc, [k, v]) => {
    acc[k] = { DataType: 'String', StringValue: v };
    return acc;
  }, {});

  const client = new SQSClient({});
  await client.send(new SendMessageCommand({
    QueueUrl: queueUrl,
    MessageBody: JSON.stringify(body),
    MessageAttributes: messageAttributes,
  }));
}
```

### Consumer (extract from MessageAttribute)

```javascript
const { propagation, context, trace, SpanKind } = require('@opentelemetry/api');

async function processSqsMessage(sqsMessage, queueName) {
  const carrier = Object.entries(sqsMessage.MessageAttributes || {}).reduce((acc, [k, v]) => {
    acc[k] = v.StringValue;
    return acc;
  }, {});

  const producerContext = propagation.extract(context.active(), carrier);
  const producerSpanContext = trace.getSpanContext(producerContext);

  // GOOD — new root span linked to producer; do NOT set parent
  tracer.startActiveSpan(
    'receive ' + queueName,
    {
      kind: SpanKind.CONSUMER,
      links: producerSpanContext ? [{ context: producerSpanContext }] : [],
    },
    context.active(),
    async (span) => {
      try {
        span.setAttribute('messaging.system', 'aws_sqs');
        span.setAttribute('messaging.destination.name', queueName);
        span.setAttribute('messaging.operation', 'receive');
        await processMessage(sqsMessage);
        span.end();
      } catch (err) {
        span.recordException(err);
        span.setStatus({ code: require('@opentelemetry/api').SpanStatusCode.ERROR, message: err.message });
        span.end();
        throw err;
      }
    }
  );
}
```

## Verification

```bash
# Check producer spans
tsuga spans search --query "context.service.name:<producer-service> messaging.system:kafka" --max-results 5

# Check consumer spans and Links field
tsuga spans search --query "context.service.name:<consumer-service> messaging.operation:receive" --max-results 5
```

If consumer spans appear as children (not linked roots) of the producer span, verify:
1. `links` array is populated with `producerSpanContext`
2. The third argument to `startActiveSpan` is `context.active()` not `producerContext`
