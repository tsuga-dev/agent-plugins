# Endpoint, Protocol, and Troubleshooting — PHP

> **Last verified:** 2026-03-23 | SDK: `open-telemetry/opentelemetry-php` 1.13.0 | exporter-otlp 1.4.0

## OTLP Protocol Reference

| Protocol | Port | Path auto-appended by SDK? | Notes |
|----------|------|---------------------------|-------|
| OTLP/gRPC | 4317 | No | Requires `ext-grpc` PHP extension |
| OTLP/HTTP | 4318 | **No — append manually in programmatic setup** | Default for PHP SDK |

> **Important:** Unlike most other OTel SDKs, the PHP SDK's `OtlpHttpTransportFactory` requires the **full path including `/v1/traces`** to be included in the URL when using the programmatic API. The path is NOT auto-appended in the default programmatic setup. However, when using `OTEL_EXPORTER_OTLP_ENDPOINT` with the auto-config extension, the path IS appended automatically.

Protocol defaults by path:

| Setup path | Default protocol | Default port | Notes |
|-----------|-----------------|--------------|-------|
| Programmatic `OtlpHttpTransportFactory` | `http/protobuf` | 4318 | Path must be appended manually (`/v1/traces` etc.) |
| Auto-config / env-var driven | `http/protobuf` | 4318 | Path is appended automatically |
| gRPC (opt-in) | `grpc` | 4317 | Requires `pecl install grpc` |

## Tsuga Endpoint Configuration

**HTTP/protobuf (recommended — no gRPC extension needed):**

```php
<?php

use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;
use OpenTelemetry\Contrib\Otlp\SpanExporter;
use OpenTelemetry\SDK\Trace\SpanProcessor\BatchSpanProcessor;

$endpoint  = getenv('OTEL_EXPORTER_OTLP_ENDPOINT') ?: 'https://ingest.<region>.tsuga.cloud:443';
$transport = (new OtlpHttpTransportFactory())->create(
    $endpoint . '/v1/traces',   // append signal path manually
    'application/x-protobuf',
    ['tsuga-ingestion-key' => getenv('TSUGA_INGESTION_KEY') ?: '']
);
$exporter = new SpanExporter($transport);
```

**Via environment variables (recommended for production):**

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://ingest.<region>.tsuga.cloud:443
OTEL_EXPORTER_OTLP_HEADERS=tsuga-ingestion-key=<your-key>
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_SERVICE_NAME=my-service
```

> To determine the correct service name, see `references/resource-attributes.md` → **Resolve resource attribute values**.

When using env-var-based auto-configuration, the SDK appends `/v1/traces` to `OTEL_EXPORTER_OTLP_ENDPOINT` automatically.

**gRPC (requires `ext-grpc` PHP extension):**

```bash
pecl install grpc
# Then set:
OTEL_EXPORTER_OTLP_ENDPOINT=https://ingest.<region>.tsuga.cloud:443
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
OTEL_EXPORTER_OTLP_HEADERS=tsuga-ingestion-key=<your-key>
```

gRPC is available but less common in PHP deployments due to the PECL extension requirement. HTTP/protobuf is the recommended default.

## Common Issues

### `HttpClientNotFoundException`

```
OpenTelemetry\Contrib\Otlp\HttpClientNotFoundException:
No HTTP client found. Install php-http/guzzle7-adapter.
```

**Fix:**

```bash
composer require php-http/guzzle7-adapter
```

### Double `/v1/traces` in URL

If the URL becomes `http://localhost:4318/v1/traces/v1/traces`:

- In programmatic setup: append the path to the base URL exactly once
- In env-var setup: set only the base URL (no path) in `OTEL_EXPORTER_OTLP_ENDPOINT`; the auto-config appends the path

### `buildAndRegisterGlobal()` has no effect

Symptoms: `Globals::tracerProvider()->getTracer('...')` returns a noop tracer even after SDK setup.

Cause: `getTracer()` was called before `buildAndRegisterGlobal()`. In PHP, the global provider is set at the point of calling `buildAndRegisterGlobal()`. Any tracer obtained before this call holds a reference to the noop provider.

**Fix:** Ensure `buildAndRegisterGlobal()` is called in the earliest possible bootstrap — before any framework auto-wiring or service container resolution.

### Auto-instrumentation not working

Symptoms: no spans from Laravel/Symfony even though `opentelemetry-auto-laravel` is installed.

**Most likely cause:** The `ext-opentelemetry` C extension is not installed or not enabled.

```bash
php -m | grep opentelemetry
# If absent — the auto-instrumentation packages will not work
pecl install opentelemetry
# Then enable in php.ini: extension=opentelemetry.so
```

### SSL/TLS error connecting to Tsuga

```
cURL error 60: SSL certificate problem: unable to get local issuer certificate
```

The PHP `curl` extension must have access to a CA bundle:

```bash
# Find current php.ini
php --ini

# Set in php.ini:
curl.cainfo = /etc/ssl/certs/ca-certificates.crt
openssl.cafile = /etc/ssl/certs/ca-certificates.crt
```

### PHP-FPM: no spans from worker processes

PHP-FPM spawns worker processes. Initialize the SDK per-request in PHP-FPM — inside a middleware or early in `index.php`. Do not initialize in the master process before forking, as the exporter's HTTP client connection may not be valid in child processes.

### Spans buffered but never exported (BatchSpanProcessor)

The `BatchSpanProcessor` exports on a background schedule. In PHP, there is no background thread — the batch is flushed on `$tracerProvider->shutdown()` or at PHP process exit (if `setAutoShutdown(true)` is used).

For short-lived PHP scripts:

```php
// Use SimpleSpanProcessor for CLI scripts (synchronous export per span)
use OpenTelemetry\SDK\Trace\SpanProcessor\SimpleSpanProcessor;

$tracerProvider = TracerProvider::builder()
    ->addSpanProcessor(new SimpleSpanProcessor($exporter))
    ->build();
```

## Shutdown / Flush

**Automatic (recommended):**

```php
Sdk::builder()
    ->setTracerProvider($tracerProvider)
    ->setAutoShutdown(true)   // registers PHP shutdown function automatically
    ->buildAndRegisterGlobal();
```

`setAutoShutdown(true)` registers a `register_shutdown_function` that calls `$tracerProvider->shutdown()` on process exit.

**Manual:**

```php
register_shutdown_function(function () use ($tracerProvider) {
    $tracerProvider->shutdown();
});
```

**PHP-FPM worker (fastcgi_finish_request):**

```php
// After sending response to client, flush OTel before process recycles
fastcgi_finish_request();
$tracerProvider->shutdown();
```

**Laravel queue workers (long-running):**

```php
// In AppServiceProvider or queue worker lifecycle hook:
Queue::after(function () {
    \OpenTelemetry\API\Globals::tracerProvider()->forceFlush();
});
```

**Worker lifecycle flush patterns:**

| Execution model | When to flush/shutdown | Pattern |
|----------------|------------------------|---------|
| PHP-FPM (web request) | End of every request | `setAutoShutdown(true)` or `register_shutdown_function()` |
| CLI script (one-shot) | Before `exit` | `$tracerProvider->shutdown()` at end of script |
| Long-running consumer (RoadRunner, Swoole) | After each work item + on SIGTERM | `forceFlush()` after message; `shutdown()` on SIGTERM/SIGINT |
| Laravel Octane (persistent worker) | After each request cycle | `forceFlush()` in `RequestHandled` event; `shutdown()` on worker stop |

**Common shutdown mistakes:**
- `setAutoShutdown(false)` and no manual shutdown — spans buffered in `BatchSpanProcessor` are lost
- Not handling queue worker shutdown — `BatchSpanProcessor` never flushes in persistent workers
- Calling `exit()` with non-zero code — PHP's `register_shutdown_function` still runs, but `fastcgi_finish_request()` may interfere

## Resilience: Collector Unavailable

When the OTLP collector is unreachable, the PHP OTel SDK does not throw exceptions to application code (assuming proper error handling in the shutdown function). The request continues normally.

```php
// Safe flush pattern — catch export failures
register_shutdown_function(function () use ($tracerProvider) {
    try {
        $tracerProvider->shutdown();
    } catch (\Throwable $e) {
        error_log('OTel shutdown failed (collector unavailable): ' . $e->getMessage());
        // Service has already processed the request — this is non-fatal
    }
});
```

**Disable OTel:**

```bash
OTEL_SDK_DISABLED=true php app.php
```

## PHP Extension Requirements

| Extension | Purpose | Required? |
|-----------|---------|-----------|
| `ext-opentelemetry` | Auto-instrumentation hook (C extension) | Required for auto-instrumentation; optional for manual SDK |
| `ext-curl` | HTTP transport for OTLP/HTTP | Required for HTTP export |
| `ext-grpc` | gRPC transport for OTLP/gRPC | Only if using gRPC endpoint |
| `ext-protobuf` | Native protobuf serialization | Optional — improves export performance significantly |
| `ext-mbstring` | String encoding in SDK | Usually pre-installed |

Check installed extensions:

```bash
php -m | grep -E 'opentelemetry|curl|grpc|protobuf'
```

If `ext-grpc` is missing and you're using a gRPC endpoint, the SDK will fail silently or throw on connection. Switch to the HTTP endpoint (port 4318) or install the extension.
