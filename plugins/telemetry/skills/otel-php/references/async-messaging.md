# Async Messaging — PHP OTel

> **Last verified:** 2026-03-23 | SDK: `open-telemetry/opentelemetry-php` 1.13.0 | exporter-otlp 1.4.0

## Agent Coverage Note

The PHP ecosystem has significantly less auto-instrumentation coverage for async messaging than Java. There are no auto-instrumentation packages for Kafka or SQS — all propagation must be done manually. Laravel queue jobs have a manual pattern via stored `otelContext` headers. Plan on writing inject/extract code for any message queue integration.

## Context Model: Use span Links, Not Parent-Child

Async CONSUMER spans must use **span Links** to the producer span — not parent-child relationships. The producer and consumer are separate operations in separate traces.

```php
<?php

use OpenTelemetry\API\Globals;
use OpenTelemetry\API\Trace\Span;
use OpenTelemetry\API\Trace\SpanKind;
use OpenTelemetry\API\Trace\StatusCode;
use OpenTelemetry\Context\Context;

// BAD — makes consumer appear as a child of the producer HTTP request
$span = $tracer->spanBuilder('kafka.process')
    ->setParent($extractedProducerContext)
    ->startSpan();

// GOOD — new root span linked to producer for cross-trace navigation
$span = $tracer->spanBuilder('receive orders')
    ->setNoParent()
    ->addLink(Span::fromContext($extractedProducerContext)->getContext())
    ->setSpanKind(SpanKind::KIND_CONSUMER)
    ->startSpan();
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
| `messaging.system` | Yes | `kafka`, `aws_sqs`, `rabbitmq` |
| `messaging.destination.name` | Yes | `orders`, `user-events` |
| `messaging.operation` | Yes | `publish`, `receive`, `process` |
| `messaging.message.id` | Recommended | `"msg-abc-123"` |

> Check `otel-semantic-conventions` for the full `messaging.*` namespace before adding custom attributes.

## Auto-Instrumentation Coverage

| System | Auto-instrumented? | Notes |
|--------|--------------------|-------|
| Kafka | No | Requires `rdkafka` PHP extension + manual inject/extract |
| AWS SQS | No | Requires `aws/aws-sdk-php` + manual inject/extract |
| RabbitMQ / AMQP | No | Manual inject/extract via `php-amqplib` |
| Laravel Queues | Partial | Manual context carry pattern required (see below) |

## Kafka — Manual Propagation (via rdkafka Extension)

Kafka requires the `rdkafka` PECL extension. Install via `pecl install rdkafka` or your package manager.

### Producer

```php
<?php

use OpenTelemetry\API\Globals;
use OpenTelemetry\API\Trace\Propagation\TraceContextPropagator;
use OpenTelemetry\API\Trace\SpanKind;
use OpenTelemetry\API\Trace\StatusCode;

$tracer = Globals::tracerProvider()->getTracer('my-service');

$span  = $tracer->spanBuilder('publish orders')
    ->setSpanKind(SpanKind::KIND_PRODUCER)
    ->setAttribute('messaging.system', 'kafka')
    ->setAttribute('messaging.destination.name', 'orders')
    ->setAttribute('messaging.operation', 'publish')
    ->startSpan();
$scope = $span->activate();

try {
    // Inject trace context into message headers
    $headers = [];
    TraceContextPropagator::getInstance()->inject($headers);

    $message = new \RdKafka\Message();
    // RdKafka doesn't support per-message headers in all versions;
    // store headers as JSON in message key or a dedicated header field
    $producer->produce(RD_KAFKA_PARTITION_UA, 0, json_encode([
        'payload' => $payload,
        '_otel'   => $headers,  // carry trace context in payload
    ]));
} catch (\Throwable $e) {
    $span->recordException($e);
    $span->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
    throw $e;
} finally {
    $scope->detach();
    $span->end();
}
```

### Consumer

```php
<?php

use OpenTelemetry\API\Globals;
use OpenTelemetry\API\Trace\Propagation\TraceContextPropagator;
use OpenTelemetry\API\Trace\Span;
use OpenTelemetry\API\Trace\SpanKind;
use OpenTelemetry\API\Trace\StatusCode;

$tracer = Globals::tracerProvider()->getTracer('my-service');

// Decode message and extract stored trace context
$data           = json_decode($message->payload, true);
$otelHeaders    = $data['_otel'] ?? [];

// Extract producer context
$producerContext = TraceContextPropagator::getInstance()->extract($otelHeaders);

// GOOD — new root linked to producer; do NOT use setParent()
$span  = $tracer->spanBuilder('receive orders')
    ->setNoParent()
    ->addLink(Span::fromContext($producerContext)->getContext())
    ->setSpanKind(SpanKind::KIND_CONSUMER)
    ->setAttribute('messaging.system', 'kafka')
    ->setAttribute('messaging.destination.name', 'orders')
    ->setAttribute('messaging.operation', 'receive')
    ->startSpan();
$scope = $span->activate();

try {
    processOrder($data['payload']);
} catch (\Throwable $e) {
    $span->recordException($e);
    $span->setStatus(StatusCode::STATUS_ERROR, 'kafka processing failed');
    throw $e;
} finally {
    $scope->detach();
    $span->end();
}
```

## AWS SQS — Manual Propagation

```bash
composer require aws/aws-sdk-php
```

### Producer

```php
<?php

use Aws\Sqs\SqsClient;
use OpenTelemetry\API\Trace\Propagation\TraceContextPropagator;
use OpenTelemetry\API\Trace\SpanKind;

$tracer = Globals::tracerProvider()->getTracer('my-service');
$span   = $tracer->spanBuilder('publish ' . $queueName)
    ->setSpanKind(SpanKind::KIND_PRODUCER)
    ->setAttribute('messaging.system', 'aws_sqs')
    ->setAttribute('messaging.destination.name', $queueName)
    ->setAttribute('messaging.operation', 'publish')
    ->startSpan();
$scope = $span->activate();

try {
    // Inject trace context into SQS MessageAttributes
    $traceHeaders = [];
    TraceContextPropagator::getInstance()->inject($traceHeaders);

    $messageAttributes = [];
    foreach ($traceHeaders as $key => $value) {
        $messageAttributes[$key] = [
            'DataType'    => 'String',
            'StringValue' => $value,
        ];
    }

    $sqs->sendMessage([
        'QueueUrl'         => $queueUrl,
        'MessageBody'      => json_encode($payload),
        'MessageAttributes' => $messageAttributes,
    ]);
} finally {
    $scope->detach();
    $span->end();
}
```

### Consumer

```php
<?php

use OpenTelemetry\API\Trace\Propagation\TraceContextPropagator;
use OpenTelemetry\API\Trace\Span;
use OpenTelemetry\API\Trace\SpanKind;

$messages = $sqs->receiveMessage(['QueueUrl' => $queueUrl, 'MessageAttributeNames' => ['All']]);

foreach ($messages['Messages'] as $message) {
    // Extract trace context from MessageAttributes
    $traceHeaders = [];
    foreach ($message['MessageAttributes'] ?? [] as $key => $attr) {
        $traceHeaders[$key] = $attr['StringValue'];
    }
    $producerContext = TraceContextPropagator::getInstance()->extract($traceHeaders);

    // GOOD — new root linked to producer
    $span  = $tracer->spanBuilder('receive ' . $queueName)
        ->setNoParent()
        ->addLink(Span::fromContext($producerContext)->getContext())
        ->setSpanKind(SpanKind::KIND_CONSUMER)
        ->setAttribute('messaging.system', 'aws_sqs')
        ->setAttribute('messaging.destination.name', $queueName)
        ->setAttribute('messaging.operation', 'receive')
        ->startSpan();
    $scope = $span->activate();

    try {
        processMessage(json_decode($message['Body'], true));
        $sqs->deleteMessage(['QueueUrl' => $queueUrl, 'ReceiptHandle' => $message['ReceiptHandle']]);
    } catch (\Throwable $e) {
        $span->recordException($e);
        $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_ERROR, 'sqs processing failed');
        throw $e;
    } finally {
        $scope->detach();
        $span->end();
    }
}
```

## Laravel Queue Jobs — Context Carry Pattern

Laravel jobs are serialized to JSON and executed in a separate worker process. The HTTP request context is not available when the job runs. Carry the trace context headers as a job property and re-extract in `handle()`.

```php
<?php

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use OpenTelemetry\API\Globals;
use OpenTelemetry\API\Trace\Propagation\TraceContextPropagator;
use OpenTelemetry\API\Trace\Span;
use OpenTelemetry\API\Trace\SpanKind;
use OpenTelemetry\API\Trace\StatusCode;

class ProcessOrderJob implements ShouldQueue
{
    use Queueable;

    public function __construct(
        private string $orderId,
        private array  $otelContext = []  // carry propagated headers
    ) {}

    public function handle(): void
    {
        // Extract producer context from carried headers
        $producerContext = TraceContextPropagator::getInstance()->extract($this->otelContext);

        $tracer = Globals::tracerProvider()->getTracer('my-service');

        // GOOD — new root linked to producer via span Link
        $span  = $tracer->spanBuilder('process order')
            ->setNoParent()
            ->addLink(Span::fromContext($producerContext)->getContext())
            ->setSpanKind(SpanKind::KIND_CONSUMER)
            ->setAttribute('messaging.system', 'laravel_queue')
            ->setAttribute('messaging.destination.name', 'orders')
            ->setAttribute('messaging.operation', 'process')
            ->startSpan();
        $scope = $span->activate();

        try {
            $span->setAttribute('order.id', $this->orderId);
            processOrder($this->orderId);
        } catch (\Throwable $e) {
            $span->recordException($e);
            $span->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
            throw $e;
        } finally {
            $scope->detach();
            $span->end();
        }
    }
}

// Dispatch — inject current context into headers carried with the job
$otelHeaders = [];
TraceContextPropagator::getInstance()->inject($otelHeaders);
ProcessOrderJob::dispatch($orderId, $otelHeaders);
```

## Verification

```bash
# Check producer spans
tsuga spans search --query "context.service.name:<producer-service> messaging.system:kafka" --max-results 5

# Check consumer spans and Links field
tsuga spans search --query "context.service.name:<consumer-service> messaging.operation:receive" --max-results 5
```
