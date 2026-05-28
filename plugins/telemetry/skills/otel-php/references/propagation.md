# Distributed Context Propagation — PHP

> **Last verified:** 2026-03-23 | SDK: `open-telemetry/opentelemetry-php` 1.13.0 | exporter-otlp 1.4.0

## Overview

Trace context must be explicitly propagated across service boundaries. The W3C TraceContext headers (`traceparent`, `tracestate`) carry the trace ID and span ID between services. With auto-instrumentation packages, HTTP propagation for supported frameworks is automatic. For custom transports, explicit extract/inject is required.

> **Async messaging propagation (Kafka, SQS, Laravel Queue):** See [async-messaging.md](async-messaging.md) for span Links model, full inject/extract patterns, and auto-instrumentation coverage table.

## Inbound: Server Context Extraction

**Auto-instrumentation (Laravel, Symfony, PSR-15):** Fully automatic when `ext-opentelemetry` is installed and the corresponding `opentelemetry-auto-*` package is present. The middleware reads `traceparent` from incoming request headers and creates a child span.

**Manual extraction (plain PHP / custom framework):**

```php
<?php

use OpenTelemetry\API\Globals;
use OpenTelemetry\API\Trace\Propagation\TraceContextPropagator;
use OpenTelemetry\Context\Context;

// Extract parent context from $_SERVER (Apache/Nginx sets HTTP_* keys)
function extractTraceContext(): Context {
    $headers = [];
    foreach ($_SERVER as $key => $value) {
        if (str_starts_with($key, 'HTTP_')) {
            $headerName = strtolower(str_replace('_', '-', substr($key, 5)));
            $headers[$headerName] = $value;
        }
    }
    return TraceContextPropagator::getInstance()->extract($headers);
}

// PSR-7 ServerRequest
function extractFromPsr7(\Psr\Http\Message\ServerRequestInterface $request): Context {
    $headers = [];
    foreach ($request->getHeaders() as $name => $values) {
        $headers[strtolower($name)] = implode(',', $values);
    }
    return TraceContextPropagator::getInstance()->extract($headers);
}

// Use in a handler
$parentCtx = extractTraceContext();
$tracer    = Globals::tracerProvider()->getTracer('my-service');

$span  = $tracer->spanBuilder('handle request')
    ->setParent($parentCtx)
    ->startSpan();
$scope = $span->activate();
try {
    handleRequest();
} finally {
    $scope->detach();
    $span->end();
}
```

## Outbound: Client Context Injection

**Auto-instrumentation (PSR-18, Guzzle):** Automatic when `opentelemetry-auto-psr18` or `opentelemetry-auto-guzzle` is installed and `ext-opentelemetry` is present.

**Manual injection with Guzzle:**

```php
<?php

use GuzzleHttp\Client;
use OpenTelemetry\API\Trace\Propagation\TraceContextPropagator;

function callDownstream(string $url): string {
    $headers = ['Content-Type' => 'application/json'];

    // Inject current span context into headers
    TraceContextPropagator::getInstance()->inject($headers);
    // $headers now contains: ['traceparent' => '00-...', 'Content-Type' => '...']

    $client   = new Client();
    $response = $client->get($url, ['headers' => $headers]);
    return $response->getBody()->getContents();
}
```

**Manual injection with PHP's `curl`:**

```php
<?php

use OpenTelemetry\API\Trace\Propagation\TraceContextPropagator;

function curlCallDownstream(string $url): string {
    $headers = [];
    TraceContextPropagator::getInstance()->inject($headers);

    // Convert to curl header format: ["Header-Name: value"]
    $curlHeaders = array_map(fn($k, $v) => "$k: $v", array_keys($headers), $headers);

    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_HTTPHEADER, $curlHeaders);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    $result = curl_exec($ch);
    curl_close($ch);
    return $result;
}
```

## Anti-Pattern: Do Not Merge Separate Workflows

Creating a child span that parents an unrelated workflow produces misleading traces. Each independent background job or queue consumer should start a new root span and **link** to the producer trace rather than making it a parent.

```php
// WRONG — makes consumer appear as child of the HTTP request that enqueued it
$span = $tracer->spanBuilder('process job')
    ->setParent($extractedProducerContext)
    ->startSpan();

// CORRECT — new root, linked to producer for cross-trace navigation
$span = $tracer->spanBuilder('process job')
    ->setNoParent()
    ->addLink(\OpenTelemetry\API\Trace\Span::fromContext($extractedProducerContext)->getContext())
    ->startSpan();
```

## Configuring Propagators

The default propagator is W3C TraceContext + W3C Baggage. Add `b3` only when interoperating with Zipkin-instrumented services or a mesh configured for B3. To confirm whether B3 is in use, look for `X-B3-TraceId` headers in captured traffic.

```php
<?php

use OpenTelemetry\API\Trace\Propagation\TraceContextPropagator;
use OpenTelemetry\Context\Propagation\MultiTextMapPropagator;
use OpenTelemetry\Extension\Propagator\B3\B3MultiPropagator;

// Programmatic: W3C TraceContext + Baggage (default)
// No code needed — the default is correct for all new services

// Programmatic: add B3 for legacy interop
$propagator = new MultiTextMapPropagator([
    TraceContextPropagator::getInstance(),
    B3MultiPropagator::getInstance(),
]);
```

Via env var:

```bash
# Default — use for all new services
OTEL_PROPAGATORS=tracecontext,baggage

# Add B3 for legacy interop only
OTEL_PROPAGATORS=tracecontext,baggage,b3multi
```

## Tsuga Trace Continuity Validation

After instrumenting propagation, verify parent/child linkage:

```bash
tsuga spans search --query "context.service.name:<caller-service>" --max-results 5
# Note traceId values from results

tsuga spans search --query "context.service.name:<callee-service> traceId:<trace-id>"
# parentSpanId on callee spans must match spanId from caller spans
```
