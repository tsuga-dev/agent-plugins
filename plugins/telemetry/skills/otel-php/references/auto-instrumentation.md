# Auto-Instrumentation — PHP

## Overview

PHP OTel provides two auto-instrumentation paths:
1. **Composer-based packages** — install individual `open-telemetry/opentelemetry-auto-*` packages that hook into supported frameworks via PHP's extension mechanism or bootstrap patching
2. **OpenTelemetry PHP extension** — a compiled C extension (`ext-opentelemetry`) that enables zero-code auto-instrumentation similar to Java's agent

## Composer-Based Auto-Instrumentation

Install framework-specific instrumentation packages:

```bash
# Core + exporter
composer require \
    open-telemetry/api:^1.8 \
    open-telemetry/sdk:^1.13 \
    open-telemetry/exporter-otlp:^1.4 \
    php-http/guzzle7-adapter

# Framework auto-instrumentation
composer require open-telemetry/opentelemetry-auto-laravel   # Laravel
composer require open-telemetry/opentelemetry-auto-symfony   # Symfony
composer require open-telemetry/opentelemetry-auto-psr15     # PSR-15 HTTP middleware
composer require open-telemetry/opentelemetry-auto-psr18     # PSR-18 HTTP client
composer require open-telemetry/opentelemetry-auto-guzzle    # Guzzle HTTP
```

> **PSR-18 requirement:** `php-http/guzzle7-adapter` provides the required PSR-18 HTTP client for the OTLP HTTP exporter. Without it, the exporter throws `HttpClientNotFoundException` at runtime.

## SDK Initialization (Required)

Auto-instrumentation packages still require the SDK to be initialized. This typically goes in a bootstrap file (`bootstrap.php`, `public/index.php`, or a service provider):

```php
<?php

use OpenTelemetry\API\Globals;
use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;
use OpenTelemetry\Contrib\Otlp\SpanExporter;
use OpenTelemetry\SDK\Common\Attribute\Attributes;
use OpenTelemetry\SDK\Resource\ResourceInfo;
use OpenTelemetry\SDK\Sdk;
use OpenTelemetry\SDK\Trace\Sampler\AlwaysOnSampler;
use OpenTelemetry\SDK\Trace\SpanProcessor\BatchSpanProcessor;
use OpenTelemetry\SDK\Trace\TracerProvider;
// ResourceAttributes is deprecated; prefer OpenTelemetry\SemConv\Attributes\ServiceAttributes
use OpenTelemetry\SemConv\ResourceAttributes;

$resource = ResourceInfo::create(Attributes::create([
    ResourceAttributes::SERVICE_NAME    => getenv('OTEL_SERVICE_NAME') ?: 'my-service',
    ResourceAttributes::SERVICE_VERSION => '1.0.0',
    'deployment.environment.name'       => getenv('APP_ENV') ?: 'production',
]));

$endpoint  = getenv('OTEL_EXPORTER_OTLP_ENDPOINT') ?: 'http://localhost:4318';
$transport = (new OtlpHttpTransportFactory())->create(
    $endpoint . '/v1/traces',
    'application/x-protobuf'
);
$exporter = new SpanExporter($transport);

$tracerProvider = TracerProvider::builder()
    ->addSpanProcessor(new BatchSpanProcessor($exporter))
    ->setResource($resource)
    ->setSampler(new AlwaysOnSampler())
    ->build();

Sdk::builder()
    ->setTracerProvider($tracerProvider)
    ->setAutoShutdown(true)
    ->buildAndRegisterGlobal();
```

## What Gets Covered Automatically

| Library | Package |
|---|---|
| Laravel (routes, middleware, queues) | `opentelemetry-auto-laravel` |
| Symfony (HttpKernel, requests) | `opentelemetry-auto-symfony` |
| PSR-15 middleware stack | `opentelemetry-auto-psr15` |
| PSR-18 HTTP client calls | `opentelemetry-auto-psr18` |
| Guzzle HTTP client | `opentelemetry-auto-guzzle` |
| PDO database calls | `opentelemetry-auto-pdo` |
| MongoDB | `opentelemetry-auto-mongodb` |
| Slim framework | `opentelemetry-auto-slim` |

## PHP Extension (ext-opentelemetry)

For full zero-code instrumentation without Composer package changes:

```bash
pecl install opentelemetry
echo "extension=opentelemetry.so" >> php.ini
```

With the extension installed, supported frameworks are automatically instrumented when `OTEL_*` environment variables are set — no `buildAndRegisterGlobal()` call needed.

```bash
OTEL_PHP_AUTOLOAD_ENABLED=true
OTEL_SERVICE_NAME=my-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
php public/index.php
```

The extension itself requires PHP 8.0+, but the OTel SDK requires PHP 8.1+. In practice, use PHP 8.1+ for any OTel-instrumented application.

## What Needs Manual Instrumentation

Even with auto-instrumentation, you need manual spans for:

- Business logic not tied to a framework route/middleware (e.g., `order.validate`, `payment.process`)
- Custom queue handlers not using Laravel Queues or Symfony Messenger
- Long-running PHP-CLI scripts (not HTTP requests)
- Batch processing loops where per-item spans are meaningful

```php
<?php
use OpenTelemetry\API\Globals;

$tracer = Globals::tracerProvider()->getTracer('my-service', '1.0.0');

$span  = $tracer->spanBuilder('order.validate')->startSpan();
$scope = $span->activate();
try {
    validateOrder($order);
    $span->setAttribute('order.valid', true);
} catch (\Throwable $e) {
    $span->recordException($e);
    $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_ERROR, $e->getMessage());
    throw $e;
} finally {
    $scope->detach();
    $span->end();
}
```

## Verifying Auto-Instrumentation

```bash
tsuga spans search --query "context.service.name:my-service" --max-results 5
# Look for spans like "HTTP GET /users/{id}", "PDO execute", "Laravel queue job"
```
