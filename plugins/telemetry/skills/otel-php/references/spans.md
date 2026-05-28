# Span Naming, Kind, and Status Rules — PHP

> **Last verified:** 2026-03-23 | SDK: `open-telemetry/opentelemetry-php` 1.13.0 | exporter-otlp 1.4.0
>
> See also: `otel-semantic-conventions` skill for attribute naming; `otel-reference.md` for instrument types.

## Span Naming

**Pattern:** `{verb} {object}` in sentence case. Low-cardinality — no IDs, no raw paths.

| BAD | GOOD | Why |
|-----|------|-----|
| `"GET /users/{$userId}/orders"` | `GET /users/{id}/orders` | Variable interpolation creates unbounded cardinality |
| `processOrder` | `process order` | Space-separated verb-object |
| `dbQuery` | `SELECT orders` | Include operation and object |

```php
// BAD
$span = $tracer->spanBuilder("GET /users/{$userId}/orders")->startSpan();

// GOOD
$span = $tracer->spanBuilder('GET /users/{id}/orders')
    ->setAttribute('user.id', $userId)
    ->startSpan();
```

## Span Kind Decision Tree

| Scenario | Kind |
|----------|------|
| Inbound HTTP handler | `SpanKind::KIND_SERVER` |
| Outbound HTTP, DB call | `SpanKind::KIND_CLIENT` |
| Publishing to Kafka/SQS/RabbitMQ | `SpanKind::KIND_PRODUCER` |
| Consuming from queue | `SpanKind::KIND_CONSUMER` |
| Local logic (no I/O) | `SpanKind::KIND_INTERNAL` |

```php
<?php

use OpenTelemetry\API\Trace\SpanKind;

// Inbound
$span = $tracer->spanBuilder('POST /orders')
    ->setSpanKind(SpanKind::KIND_SERVER)
    ->startSpan();

// Outbound
$span = $tracer->spanBuilder('GET products-service')
    ->setSpanKind(SpanKind::KIND_CLIENT)
    ->startSpan();
```

## HTTP Status → Span Status Mapping

| Span Kind | HTTP 4xx | HTTP 5xx |
|-----------|----------|----------|
| SERVER | **UNSET** (server did its job) | ERROR |
| CLIENT | **ERROR** (call failed) | ERROR |

```php
<?php

use OpenTelemetry\API\Trace\StatusCode;

// Server span: 400 is NOT an error
if ($statusCode >= 500) {
    $span->setStatus(StatusCode::STATUS_ERROR, 'Internal server error');
}
// 4xx on server: leave as default UNSET

// Client span: 4xx IS an error
if ($statusCode >= 400) {
    $span->setStatus(StatusCode::STATUS_ERROR, "HTTP {$statusCode}");
}
```

## Headless Operations Pattern

```php
// BAD: scheduled/queue method has no parent span context → orphan child spans
public function runNightlyCleanup(): void {
    $span = $tracer->spanBuilder('query-stale-records')->startSpan();  // Orphan!
}

// GOOD: create SERVER root span wrapping the entire task
public function runNightlyCleanup(): void {
    $rootSpan = $tracer->spanBuilder('nightly-cleanup')
        ->setSpanKind(SpanKind::KIND_SERVER)
        ->setAttribute('task.name', 'nightly-cleanup')
        ->setAttribute('task.trigger', 'cron')
        ->startSpan();
    $scope = $rootSpan->activate();
    try {
        $child      = $tracer->spanBuilder('query-stale-records')->startSpan();
        $childScope = $child->activate();
        try {
            // work
        } finally {
            $childScope->detach();
            $child->end();
        }
    } finally {
        $scope->detach();
        $rootSpan->end();
    }
}
```

## Span Hygiene Rules

- **< 10 INTERNAL spans per trace** — more indicates over-instrumentation
- **< 20 spans under 5ms** — short spans add noise
- **No orphan spans** — every span except root must have a parent
- **Root spans cannot be CLIENT or PRODUCER**
- **Error spans must have a description** — `$span->setStatus(StatusCode::STATUS_ERROR, 'description')`

## Span Budget

| Operation type | Instrument? | Notes |
|----------------|-------------|-------|
| Incoming HTTP request | Always | Auto-instrumentation covers this with ext-opentelemetry |
| Outgoing HTTP / gRPC call | Always | PSR-18 auto-instrumentation covers this |
| DB query | Always | PDO/Doctrine auto-instrumentation available |
| External service call | Always | — |
| Business transaction (order.place, payment.charge) | Yes | Manual span |
| Internal helper function | Skip | Unless measurably slow or failure-prone |
| Utility called thousands of times per request | Skip | Creates noise; use metric instead |
| Loop iteration (per-item span in a batch) | Only if needed | Confirm sampling is in place first |

Anti-pattern: instrumenting every method. The span budget goal is minimum spans needed to diagnose failures and measure latency at service boundaries.

## Workflow Boundaries

**Rule:** Same user operation across services → continue the trace (propagate W3C `traceparent`). Separate operations, separate queue deliveries, or separate scheduled jobs → new root span.

Never propagate a parent context from one unrelated job into another.

### Continue the trace (outbound call)

```php
<?php

use OpenTelemetry\API\Trace\Propagation\TraceContextPropagator;

// Inject current context into outbound HTTP headers
$headers = ['Content-Type' => 'application/json'];
TraceContextPropagator::getInstance()->inject($headers);
// $headers now contains traceparent (and tracestate if set)

$client = new \GuzzleHttp\Client();
$client->post('https://downstream-service/api', ['headers' => $headers]);
```

### New root span (scheduled job or batch)

```php
<?php

use OpenTelemetry\API\Trace\SpanKind;

// setNoParent() creates a true root — no inherited parent context
$rootSpan = $tracer->spanBuilder('nightly-cleanup')
    ->setNoParent()
    ->setSpanKind(SpanKind::KIND_SERVER)
    ->setAttribute('task.name', 'nightly-cleanup')
    ->setAttribute('task.trigger', 'cron')
    ->startSpan();
$scope = $rootSpan->activate();
try {
    doWork();
} finally {
    $scope->detach();
    $rootSpan->end();
}
```

### Related but not parent-child (async / queue)

```php
<?php

use OpenTelemetry\API\Trace\Span;
use OpenTelemetry\API\Trace\SpanKind;

// addLink() connects traces for navigation without making one a child of the other
$span = $tracer->spanBuilder('process order')
    ->setNoParent()
    ->addLink(Span::fromContext($producerContext)->getContext())   // link to producer trace
    ->setSpanKind(SpanKind::KIND_CONSUMER)
    ->startSpan();
```

> **→** `references/async-messaging.md` — full Kafka, SQS, Laravel Queue patterns with semconv.
