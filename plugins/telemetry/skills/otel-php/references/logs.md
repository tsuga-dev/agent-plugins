# Logs — PHP OTel

> **Last verified:** 2026-03-23 | SDK: `open-telemetry/opentelemetry-php` 1.13.0 | exporter-otlp 1.4.0

> OTLP log export via the Monolog OTel handler is the production path for PHP. Also support stdout JSON logs via Monolog for Collector `filelog` ingestion as a complementary path.

## Path Selection

| Scenario | Path |
|----------|------|
| Monolog already in use + need trace correlation | **Path A** — Monolog OTel handler via `opentelemetry-logger-monolog` |
| Need trace_id in logs without OTel log pipeline | **Path B** — Monolog custom Processor (inject trace context) |
| Raw PSR-3 logger, no Monolog | **Path C** — manual trace context injection into log context array |

## Path A — Monolog OTel Handler (Recommended)

The `opentelemetry-logger-monolog` package bridges Monolog log records into the OTel log pipeline and injects `trace_id`, `span_id`, and `trace_flags` automatically.

**Install:**

```bash
composer require open-telemetry/opentelemetry-logger-monolog monolog/monolog
```

**Setup:**

```php
<?php

use Monolog\Logger;
use Monolog\Handler\StreamHandler;
use Monolog\Formatter\JsonFormatter;
use OpenTelemetry\Contrib\Logs\Monolog\Handler as OtelHandler;
use OpenTelemetry\API\Globals;

// JSON stdout handler — picked up by Collector filelog receiver
$stdoutHandler = new StreamHandler('php://stdout');
$stdoutHandler->setFormatter(new JsonFormatter());

// OTel handler — forwards log records into the OTel log pipeline
$otelHandler = new OtelHandler(
    Globals::loggerProvider(),
    \Monolog\Level::Debug
);

$logger = new Logger('my-service');
$logger->pushHandler($stdoutHandler);
$logger->pushHandler($otelHandler);

$logger->info('user action', ['user_id' => 123]);
```

The OTel handler:
1. Forwards log records to the OTel log pipeline (visible in Tsuga as log telemetry)
2. Auto-injects `trace_id`, `span_id`, `trace_flags` from the current span context

## Path B — Monolog Processor (Trace Context Only)

Use when you want `trace_id` in logs but do not need the full OTel log pipeline.

```php
<?php

use Monolog\LogRecord;
use Monolog\Processor\ProcessorInterface;
use OpenTelemetry\API\Trace\Span;

class TraceContextProcessor implements ProcessorInterface
{
    public function __invoke(LogRecord $record): LogRecord
    {
        $ctx = Span::getCurrent()->getContext();
        if ($ctx->isValid()) {
            return $record->with(extra: array_merge($record->extra, [
                'trace_id'    => $ctx->getTraceId(),
                'span_id'     => $ctx->getSpanId(),
                'trace_flags' => $ctx->getTraceFlags(),
            ]));
        }
        return $record;
    }
}

$logger->pushProcessor(new TraceContextProcessor());
```

**Output with trace context:**

```json
{
  "message": "user action",
  "context": {"user_id": 123},
  "extra": {
    "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
    "span_id": "00f067aa0ba902b7",
    "trace_flags": 1
  }
}
```

## Path C — Manual PSR-3 Injection

```php
<?php

use OpenTelemetry\API\Trace\Span;

function logWithTraceContext(\Psr\Log\LoggerInterface $logger, string $message, array $context = []): void
{
    $spanCtx = Span::getCurrent()->getContext();
    if ($spanCtx->isValid()) {
        $context['trace_id']    = $spanCtx->getTraceId();
        $context['span_id']     = $spanCtx->getSpanId();
        $context['trace_flags'] = $spanCtx->getTraceFlags();
    }
    $logger->info($message, $context);
}
```

## PHP-FPM Model Note

PHP-FPM is synchronous and process-per-request. There are no threading concerns — each request runs in an isolated process, so MDC/context leaking across threads is not a concern (unlike Java thread pools). The OTel span context is local to the current request process.

## Swoole / RoadRunner Context Note

Swoole and RoadRunner run as long-lived processes handling multiple requests concurrently via coroutines or workers. The OTel span context must be managed per-coroutine or per-worker. The standard `Span::getCurrent()` approach works for synchronous PHP-FPM; for Swoole coroutines, use a coroutine-aware context storage. Consult the `ext-opentelemetry` documentation for Swoole-compatible context propagation.

## Collector filelog Setup

For PHP stdout JSON logs picked up by the Collector:

```yaml
# otel-collector-config.yaml (excerpt)
receivers:
  filelog:
    include: [/var/log/php/*.log]
    operators:
      - type: json_parser
        timestamp:
          parse_from: attributes.datetime
          layout: '%Y-%m-%dT%H:%M:%S.%f%z'
```

See `otel-collector` skill for full `filelog` receiver configuration.

## Verification

```bash
# Confirm logs arrive with trace correlation
tsuga logs search --query "context.service.name:<your-service> trace_id:*" --max-results 3

# If trace_id is present but spans are not linking
tsuga spans search --query "context.service.name:<your-service> traceId:<trace-id-from-log>"
```

If verification fails:
- `trace_id` absent from logs → `tsuga-debug-missing-trace-propagation`
- Zero log results → `tsuga-debug-no-data`
