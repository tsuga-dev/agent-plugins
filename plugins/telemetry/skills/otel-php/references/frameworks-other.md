# PHP Framework Recipes — PSR-15, Slim, and Plain PHP

## Span Lifecycle Rules (All Frameworks)

PHP OTel has strict lifecycle rules that differ from other languages:

```php
// ALWAYS follow this pattern — both detach() and end() are required in finally
$span  = $tracer->spanBuilder('op')->startSpan();
$scope = $span->activate();
try {
    doWork();
} catch (\Throwable $e) {
    $span->recordException($e);
    $span->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
    throw $e;
} finally {
    $scope->detach();  // REQUIRED — restores context; must be called before end()
    $span->end();      // REQUIRED — records span duration
}
```

## Lifecycle Logging

Structured log events correlated with OTel trace context.

```php
<?php
use OpenTelemetry\API\Trace\Span;

// Helper: get current trace context for log records
function otelLogContext(): array {
    $span = Span::getCurrent();
    $ctx = $span->getContext();
    if ($ctx->isValid()) {
        return [
            'trace_id' => $ctx->getTraceId(),
            'span_id'  => $ctx->getSpanId(),
        ];
    }
    return [];
}

// Structured JSON log helper
function structuredLog(string $level, string $message, array $fields = []): void {
    $entry = array_merge([
        'timestamp' => (new DateTime())->format(DateTime::RFC3339_EXTENDED),
        'level'     => $level,
        'message'   => $message,
        'service'   => getenv('OTEL_SERVICE_NAME') ?: 'unknown',
    ], otelLogContext(), $fields);
    error_log(json_encode($entry));
}

// --- Service startup ---
structuredLog('INFO', 'service starting', [
    'version'       => getenv('APP_VERSION') ?: 'unknown',
    'environment'   => getenv('APP_ENV') ?: 'unknown',
    'otlp_endpoint' => getenv('OTEL_EXPORTER_OTLP_ENDPOINT') ?: 'not set',
]);

// --- Request lifecycle (middleware / front controller) ---
structuredLog('INFO', 'request received', [
    'method' => $_SERVER['REQUEST_METHOD'],
    'path'   => $_SERVER['REQUEST_URI'],
]);

// ... handle request ...

structuredLog('INFO', 'request completed', [
    'method' => $_SERVER['REQUEST_METHOD'],
    'path'   => $_SERVER['REQUEST_URI'],
    'status' => http_response_code(),
]);

// --- Graceful shutdown ---
register_shutdown_function(function() {
    structuredLog('INFO', 'service shutting down');
    // tracer provider shutdown happens here
});
```

> PHP is request-scoped — "service startup" logs run once at bootstrap (or in a long-running worker), and "graceful shutdown" runs at the end of each request or worker shutdown.

## Microservices Propagation Pattern

Two-service HTTP call: caller injects trace context, callee extracts and creates a child span.

**Caller service (outbound HTTP with Guzzle):**

```php
<?php
use GuzzleHttp\Client;
use OpenTelemetry\API\Globals;
use OpenTelemetry\Context\Context;
use GuzzleHttp\Psr7\Request;

// Guzzle middleware to inject W3C trace context
$propagator = Globals::propagator();

$stack = \GuzzleHttp\HandlerStack::create();
$stack->push(function (callable $handler) use ($propagator) {
    return function (\Psr\Http\Message\RequestInterface $request, array $options) use ($handler, $propagator) {
        $carrier = [];
        $propagator->inject($carrier, \OpenTelemetry\Context\Propagation\ArrayAccessGetterSetter::getInstance(), Context::getCurrent());
        foreach ($carrier as $key => $value) {
            $request = $request->withHeader($key, $value);
        }
        return $handler($request, $options);
    };
});

$client = new Client(['handler' => $stack]);

$tracer = Globals::tracerProvider()->getTracer('caller-service');
$span = $tracer->spanBuilder('call.user-service')->startSpan();
$scope = $span->activate();

try {
    $response = $client->get('http://user-service/users/123');
    // W3C traceparent header injected automatically by middleware
} finally {
    $scope->detach();
    $span->end();
}
```

**Callee service (inbound HTTP — Laravel/Slim):**

```php
<?php
use OpenTelemetry\API\Globals;
use OpenTelemetry\Context\Propagation\ArrayAccessGetterSetter;

// Extract trace context from incoming request headers
$propagator = Globals::propagator();
$context = $propagator->extract(
    getallheaders(),
    ArrayAccessGetterSetter::getInstance()
);

$tracer = Globals::tracerProvider()->getTracer('user-service');
$span = $tracer->spanBuilder('handle.get_user')
    ->setParent($context)   // child of caller's span
    ->startSpan();
$scope = $span->activate();

try {
    // handle request — this span is a child of the caller's span
} finally {
    $scope->detach();
    $span->end();
}
```

**Validate in Tsuga:** Check that the callee's root span has `parent_span_id` matching the caller's span in the same trace.

## Slim Framework

```php
<?php
// Bootstrap OTel before Slim app setup
require_once 'vendor/autoload.php';

use OpenTelemetry\API\Globals;
use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;
use OpenTelemetry\Contrib\Otlp\SpanExporter;
use OpenTelemetry\SDK\Sdk;
use OpenTelemetry\SDK\Trace\SpanProcessor\SimpleSpanProcessor;
use OpenTelemetry\SDK\Trace\TracerProvider;
use OpenTelemetry\SDK\Resource\ResourceInfoFactory;
use Slim\Factory\AppFactory;
use OpenTelemetry\Contrib\Instrumentation\Slim\SlimInstrumentation;

// SDK setup
$transport = (new OtlpHttpTransportFactory())->create('http://localhost:4318/v1/traces', 'application/x-protobuf');
$exporter = new SpanExporter($transport);
$tracerProvider = new TracerProvider(
    new SimpleSpanProcessor($exporter),
    null,
    ResourceInfoFactory::defaultResource()
);
Sdk::builder()->setTracerProvider($tracerProvider)->buildAndRegisterGlobal();

// Slim auto-instrumentation (via opentelemetry-auto-slim package)
SlimInstrumentation::register();

$app = AppFactory::create();

$app->get('/hello/{name}', function ($request, $response, $args) {
    // Span is automatically created by SlimInstrumentation
    // Add custom attributes via current span
    $span = \OpenTelemetry\API\Globals::tracerProvider()
        ->getTracer('my-app')
        ->spanBuilder('business-logic')
        ->startSpan();

    try {
        $response->getBody()->write("Hello, " . $args['name']);
        return $response;
    } finally {
        $span->end();
    }
});

$app->run();

// Flush before FPM request ends
$tracerProvider->shutdown();
```

**Package:** `open-telemetry/opentelemetry-auto-slim` (auto-instrumentation) or manual middleware.

**Context propagation:** Slim instrumentation extracts W3C traceparent from incoming request headers automatically.
