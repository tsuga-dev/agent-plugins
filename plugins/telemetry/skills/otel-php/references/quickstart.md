# Quick Start — PHP OTel

> **Last verified:** 2026-03-23 | SDK: `open-telemetry/opentelemetry-php` 1.x

> Run `php --version` — PHP 8.1+ required for SDK 1.13.x. If below 8.1, no compatible SDK version exists — stop and report the runtime version to the user.

## Step 1 — Install the C Extension (Required for Auto-Instrumentation)

> **Critical:** The `ext-opentelemetry` C extension is required for auto-instrumentation. Composer packages alone will not intercept framework hooks without it. If you only need manual SDK instrumentation, the extension is optional but still recommended.

```bash
# Via PECL (most environments)
pecl install opentelemetry

# Enable in php.ini
echo "extension=opentelemetry.so" >> $(php --ini | grep "Loaded Configuration" | awk '{print $NF}')

# Verify
php -m | grep opentelemetry
# Expected output: opentelemetry
```

On Alpine Linux / Docker:

```dockerfile
RUN apk add --no-cache $PHPIZE_DEPS \
    && pecl install opentelemetry \
    && docker-php-ext-enable opentelemetry
```

## Step 2 — Install Composer Packages

```bash
composer require \
    open-telemetry/api \
    "open-telemetry/sdk:^1.13" \
    "open-telemetry/exporter-otlp:^1.4" \
    open-telemetry/opentelemetry-logger-monolog \
    php-http/guzzle7-adapter
```

For gRPC transport (optional — requires `ext-grpc`):

```bash
composer require open-telemetry/transport-grpc
```

> **PSR-18 requirement:** `php-http/guzzle7-adapter` provides the PSR-18 HTTP client required by the OTLP HTTP exporter. Without it, the exporter throws `HttpClientNotFoundException` at runtime.

**For auto-instrumentation (requires `ext-opentelemetry` installed first):**

```bash
# Laravel
composer require open-telemetry/opentelemetry-auto-laravel

# Symfony
composer require open-telemetry/opentelemetry-auto-symfony

# PSR-15 middleware / PSR-18 HTTP client
composer require open-telemetry/opentelemetry-auto-psr15 \
                 open-telemetry/opentelemetry-auto-psr18
```

## Step 3 — SDK Initialization

Create a bootstrap file (e.g., `bootstrap-otel.php`, loaded from `index.php` or a framework service provider):

```php
<?php

use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;
use OpenTelemetry\Contrib\Otlp\SpanExporter;
use OpenTelemetry\Contrib\Otlp\LogsExporter;
use OpenTelemetry\Contrib\Otlp\MetricExporter;
use OpenTelemetry\SDK\Common\Attribute\Attributes;
use OpenTelemetry\SDK\Logs\LoggerProvider;
use OpenTelemetry\SDK\Logs\Processor\BatchLogRecordProcessor;
use OpenTelemetry\SDK\Metrics\MeterProvider;
use OpenTelemetry\SDK\Metrics\MetricReader\ExportingReader;
use OpenTelemetry\SDK\Resource\ResourceInfo;
use OpenTelemetry\SDK\Resource\ResourceInfoFactory;
use OpenTelemetry\SDK\Sdk;
use OpenTelemetry\SDK\Trace\Sampler\AlwaysOnSampler;
use OpenTelemetry\SDK\Trace\SpanProcessor\BatchSpanProcessor;
use OpenTelemetry\SDK\Trace\TracerProvider;
// ResourceAttributes is deprecated; prefer OpenTelemetry\SemConv\Attributes\ServiceAttributes
use OpenTelemetry\SemConv\ResourceAttributes;

// ResourceInfoFactory::defaultResource() reads OTEL_SERVICE_NAME and
// OTEL_RESOURCE_ATTRIBUTES automatically. Do NOT hardcode service.name.
$resource = ResourceInfoFactory::defaultResource()->merge(
    ResourceInfo::create(Attributes::create([
        ResourceAttributes::SERVICE_VERSION => getenv('APP_VERSION') ?: '0.0.0',
    ]))
);

$endpoint = getenv('OTEL_EXPORTER_OTLP_ENDPOINT') ?: 'http://localhost:4318';

// TracerProvider
$traceTransport = (new OtlpHttpTransportFactory())->create(
    $endpoint . '/v1/traces',   // programmatic setup requires manual path append
    'application/x-protobuf'
);
$tracerProvider = TracerProvider::builder()
    ->addSpanProcessor(new BatchSpanProcessor(new SpanExporter($traceTransport)))
    ->setResource($resource)
    ->setSampler(new AlwaysOnSampler())
    ->build();

// MeterProvider (metrics SDK: verify stability for your version before production use)
$metricTransport = (new OtlpHttpTransportFactory())->create(
    $endpoint . '/v1/metrics',
    'application/x-protobuf'
);
$meterProvider = MeterProvider::builder()
    ->setResource($resource)
    ->addReader(new ExportingReader(new MetricExporter($metricTransport)))
    ->build();

// LoggerProvider (logs SDK: use Collector filelog receiver for production)
$logTransport = (new OtlpHttpTransportFactory())->create(
    $endpoint . '/v1/logs',
    'application/x-protobuf'
);
$loggerProvider = LoggerProvider::builder()
    ->setResource($resource)
    ->addLogRecordProcessor(new BatchLogRecordProcessor(new LogsExporter($logTransport)))
    ->build();

// Register globally — must be called before any getTracer()/getMeter() call
Sdk::builder()
    ->setTracerProvider($tracerProvider)
    ->setMeterProvider($meterProvider)
    ->setLoggerProvider($loggerProvider)
    ->setAutoShutdown(true)   // registers shutdown function; flushes on process exit
    ->buildAndRegisterGlobal();
```

> **Critical ordering rule:** `buildAndRegisterGlobal()` must be called before any `Globals::tracerProvider()->getTracer(...)` call. Any tracer obtained before this call holds a reference to the noop provider and will never export spans.

## Step 4 — Scope Management Pattern

```php
<?php

use OpenTelemetry\API\Globals;
use OpenTelemetry\API\Trace\StatusCode;
use OpenTelemetry\API\Trace\SpanKind;

$tracer = Globals::tracerProvider()->getTracer('my-service', '1.0.0');

// CORRECT — both detach() and end() in finally
$span  = $tracer->spanBuilder('process order')
    ->setSpanKind(SpanKind::KIND_SERVER)
    ->startSpan();
$scope = $span->activate();
try {
    doWork();
} catch (\Throwable $e) {
    $span->recordException($e);
    $span->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
    throw $e;
} finally {
    $scope->detach();   // REQUIRED — restores previous context
    $span->end();       // REQUIRED — records duration and exports span
}

// WRONG — end() not reached on exception; scope not detached
$span  = $tracer->spanBuilder('process order')->startSpan();
$scope = $span->activate();
doWork();          // throws → lines below never execute
$scope->detach();  // not reached
$span->end();      // not reached; span leaks
```

> `$span->activate()` returns a `ScopeInterface`. Calling `$scope->detach()` does NOT end the span — both are required. Omitting `detach()` corrupts the context stack for all subsequent code in the current process.

## Step 5 — Environment Variables

```bash
# Minimum required — see references/resource-attributes.md to resolve the correct service name
OTEL_SERVICE_NAME=my-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318   # HTTP/protobuf default

# Recommended
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production,service.version=1.4.2

# gRPC opt-in (requires ext-grpc PHP extension)
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```

> **Note:** The PHP SDK reads `OTEL_SERVICE_NAME` and `OTEL_RESOURCE_ATTRIBUTES` via `ResourceInfoFactory::defaultResource()`. Most other `OTEL_*` vars require manual `getenv()` in code. See `references/otel-reference.md` for the full env var support table.

## Step 6 — Post-Deploy Verification

```bash
# Confirm traces arrive
tsuga spans search --query "context.service.name:my-service" --max-results 5

# Confirm logs with trace correlation
tsuga logs search --query "context.service.name:my-service trace_id:*" --max-results 3

# Confirm metrics
tsuga metrics list --filter "service.name=my-service"
```

If no data: `tsuga-debug-no-data` skill.
If traces don't link across services: `tsuga-debug-missing-trace-propagation` skill.
