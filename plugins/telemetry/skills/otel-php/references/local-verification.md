# Local Verification — PHP

## Overview

Before routing telemetry to a production collector, verify PHP instrumentation by printing spans to stdout using `ConsoleSpanExporter`. There is no `OTEL_TRACES_EXPORTER=console` environment variable support in the PHP SDK — the exporter must be configured in SDK setup code. PHP's execution model requires careful attention to shutdown: FPM requests end abruptly, and CLI scripts must call `$tracerProvider->shutdown()` explicitly or spans will be lost.

## Console Span Exporter

`ConsoleSpanExporter` is included in the `open-telemetry/sdk` package. Pair it with `SimpleSpanProcessor` for synchronous, per-span output to stdout.

```php
<?php

use OpenTelemetry\API\Globals;
use OpenTelemetry\SDK\Trace\TracerProvider;
use OpenTelemetry\SDK\Trace\SpanProcessor\SimpleSpanProcessor;
use OpenTelemetry\SDK\Trace\SpanExporter\ConsoleSpanExporterFactory;
use OpenTelemetry\SDK\Resource\ResourceInfo;
// ResourceAttributes is deprecated; prefer OpenTelemetry\SemConv\Attributes\ServiceAttributes
use OpenTelemetry\SemConv\ResourceAttributes;

$resource = ResourceInfo::create(
    \OpenTelemetry\SDK\Common\Attribute\Attributes::create([
        ResourceAttributes::SERVICE_NAME => 'my-service',
    ])
);

$tracerProvider = new TracerProvider(
    new SimpleSpanProcessor((new ConsoleSpanExporterFactory())->create()),
    null,
    $resource
);

Globals::registerInitializer(function ($configurator) use ($tracerProvider) {
    return $configurator->withTracerProvider($tracerProvider);
});

$tracer = $tracerProvider->getTracer('my-service');

$span = $tracer->spanBuilder('my-operation')->startSpan();
$scope = $span->activate();

try {
    doWork();
} finally {
    $scope->detach();
    $span->end();
}
```

Each finished span is printed as a JSON object or PHP array to stdout, including trace ID, span ID, parent span ID, name, kind, attributes, and timing.

## SimpleSpanProcessor vs BatchSpanProcessor

| | `SimpleSpanProcessor` | `BatchSpanProcessor` |
|---|---|---|
| Export timing | Synchronous, on span end | Async (requires event loop or manual flush) |
| Local testing | Preferred — spans appear immediately | Requires explicit `forceFlush()` + `shutdown()` |
| Production | Acceptable for FPM (short-lived) | Preferred for daemons and async workers |

In PHP-FPM, each request is a short-lived process. `SimpleSpanProcessor` is generally the right choice even in production for FPM deployments, because there is no persistent background thread. `BatchSpanProcessor` is more appropriate for long-running PHP daemons (e.g., ReactPHP, Swoole, RoadRunner).

## Short-Lived FPM Requests and CLI Scripts

**PHP-FPM:** Register `$tracerProvider->shutdown()` in a shutdown function so it runs at the end of every request, including error cases.

```php
<?php

// Register early in request lifecycle
register_shutdown_function(function () use ($tracerProvider) {
    $tracerProvider->shutdown();
});

// ... handle request, create spans ...
```

**CLI scripts:** Call `shutdown()` explicitly in a `finally` block before the script exits.

```php
<?php

$tracer = $tracerProvider->getTracer('my-cli');
$span = $tracer->spanBuilder('job.run')->startSpan();
$scope = $span->activate();

try {
    processRecords();
} catch (\Throwable $e) {
    $span->recordException($e);
    $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_ERROR);
    throw $e;
} finally {
    $scope->detach();
    $span->end();
    // Required: flush and release exporter resources before exit
    $tracerProvider->shutdown();
}
```

Without `shutdown()` in CLI scripts, any spans buffered in `BatchSpanProcessor` are silently dropped when the process exits.

## OTEL_TRACES_EXPORTER Environment Variable

The PHP OTel SDK does not support `OTEL_TRACES_EXPORTER=console` natively. Configure the exporter explicitly in SDK setup code. To switch between local and production exporters based on environment:

```php
<?php

use OpenTelemetry\SDK\Trace\SpanExporter\ConsoleSpanExporterFactory;
use OpenTelemetry\SDK\Trace\SpanProcessor\SimpleSpanProcessor;
use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;
use OpenTelemetry\Contrib\Otlp\SpanExporter;
use OpenTelemetry\SDK\Trace\SpanProcessor\BatchSpanProcessor;

$exporterType = getenv('OTEL_TRACES_EXPORTER') ?: 'otlp';

if ($exporterType === 'console') {
    $processor = new SimpleSpanProcessor((new ConsoleSpanExporterFactory())->create());
} else {
    $endpoint  = getenv('OTEL_EXPORTER_OTLP_ENDPOINT') ?: 'http://localhost:4318';
    $transport = (new OtlpHttpTransportFactory())->create($endpoint . '/v1/traces', 'application/x-protobuf');
    $processor = new BatchSpanProcessor(new SpanExporter($transport));
}

$tracerProvider = new TracerProvider($processor, null, $resource);
```

## Local Collector with Debug Exporter

Run `otelcol-contrib` locally to validate the full OTLP export path. The `debug` exporter prints every received span and metric with full attribute detail.

```yaml
# otelcol-config.yaml — local debug collector
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

exporters:
  debug:
    verbosity: detailed

service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [debug]
    metrics:
      receivers: [otlp]
      exporters: [debug]
```

Point the PHP OTLP exporter at the local collector:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 \
OTEL_SERVICE_NAME=my-service \
php app.php
```

The `open-telemetry/exporter-otlp` package uses HTTP/protobuf to port 4318 by default. The `open-telemetry/transport-grpc` package targets port 4317.
