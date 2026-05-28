# PHP Framework Recipes — Laravel

> **Last verified:** 2026-03-23 | SDK: `open-telemetry/opentelemetry-php` 1.13.0 | exporter-otlp 1.4.0

Laravel auto-instrumentation via `open-telemetry/opentelemetry-auto-laravel` instruments routes, middleware, and queues automatically.

```bash
composer require \
    open-telemetry/api:^1.8 \
    open-telemetry/sdk:^1.13 \
    open-telemetry/exporter-otlp:^1.4 \
    open-telemetry/opentelemetry-auto-laravel \
    php-http/guzzle7-adapter
```

## Resource Initialization — GOOD vs BAD

```php
// BAD — service.name hardcoded in code; cannot change without a deploy
$resource = ResourceInfo::create(Attributes::create([
    ResourceAttributes::SERVICE_NAME => config('app.name', 'laravel-app'),
    'deployment.environment.name'    => app()->environment(),
]));

// GOOD — ResourceInfoFactory::defaultResource() reads OTEL_SERVICE_NAME automatically
use OpenTelemetry\SDK\Resource\ResourceInfoFactory;

$resource = ResourceInfoFactory::defaultResource()->merge(
    ResourceInfo::create(Attributes::create([
        ResourceAttributes::SERVICE_VERSION => config('app.version', '0.0.0'),
    ]))
);
```

**Service provider (initialize SDK before app handling requests):**

```php
<?php
// app/Providers/OpenTelemetryServiceProvider.php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use OpenTelemetry\API\Globals;
use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;
use OpenTelemetry\Contrib\Otlp\SpanExporter;
use OpenTelemetry\SDK\Common\Attribute\Attributes;
use OpenTelemetry\SDK\Resource\ResourceInfo;
use OpenTelemetry\SDK\Resource\ResourceInfoFactory;
use OpenTelemetry\SDK\Sdk;
use OpenTelemetry\SDK\Trace\Sampler\AlwaysOnSampler;
use OpenTelemetry\SDK\Trace\SpanProcessor\BatchSpanProcessor;
use OpenTelemetry\SDK\Trace\TracerProvider;
// ResourceAttributes is deprecated; prefer OpenTelemetry\SemConv\Attributes\ServiceAttributes
use OpenTelemetry\SemConv\ResourceAttributes;

class OpenTelemetryServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        // GOOD — reads OTEL_SERVICE_NAME from env automatically
        $resource = ResourceInfoFactory::defaultResource()->merge(
            ResourceInfo::create(Attributes::create([
                ResourceAttributes::SERVICE_VERSION => config('app.version', '0.0.0'),
            ]))
        );

        $endpoint  = env('OTEL_EXPORTER_OTLP_ENDPOINT', 'http://localhost:4318');
        $transport = (new OtlpHttpTransportFactory())->create(
            $endpoint . '/v1/traces',
            'application/x-protobuf'
        );

        $tracerProvider = TracerProvider::builder()
            ->addSpanProcessor(new BatchSpanProcessor(new SpanExporter($transport)))
            ->setResource($resource)
            ->setSampler(new AlwaysOnSampler())
            ->build();

        Sdk::builder()
            ->setTracerProvider($tracerProvider)
            ->setAutoShutdown(true)
            ->buildAndRegisterGlobal();
    }
}
```

Register in `config/app.php`:

```php
'providers' => [
    // ...
    App\Providers\OpenTelemetryServiceProvider::class,
],
```

**Controller with manual spans:**

```php
<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;
use OpenTelemetry\API\Globals;
use OpenTelemetry\API\Trace\StatusCode;

class OrderController extends Controller
{
    private $tracer;

    public function __construct()
    {
        $this->tracer = Globals::tracerProvider()->getTracer('laravel-app', '1.0.0');
    }

    public function store(Request $request): JsonResponse
    {
        // Laravel route span created automatically by auto-instrumentation
        // Add business logic spans as children

        $span  = $this->tracer->spanBuilder('order.validate')->startSpan();
        $scope = $span->activate();
        try {
            $validated = $request->validate([
                'user_id' => 'required|integer',
                'items'   => 'required|array|min:1',
            ]);
            $span->setAttribute('order.items', count($validated['items']));
        } catch (\Throwable $e) {
            $span->recordException($e);
            $span->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
            throw $e;
        } finally {
            $scope->detach();
            $span->end();
        }

        $orderSpan  = $this->tracer->spanBuilder('order.persist')->startSpan();
        $orderScope = $orderSpan->activate();
        try {
            $order = Order::create($validated);
            $orderSpan->setAttribute('order.id', (string) $order->id);
            return response()->json($order, 201);
        } finally {
            $orderScope->detach();
            $orderSpan->end();
        }
    }
}
```

**Laravel Queue (manual propagation):**

```php
<?php
// In Job class
use OpenTelemetry\API\Globals;
use OpenTelemetry\API\Trace\StatusCode;

class ProcessOrderJob implements ShouldQueue
{
    use Queueable;

    public function __construct(private int $orderId) {}

    public function handle(): void
    {
        $tracer = Globals::tracerProvider()->getTracer('laravel-app');
        // Auto-instrumentation creates a job span
        // Add child span for business logic
        $span  = $tracer->spanBuilder('order.process')->startSpan();
        $scope = $span->activate();
        try {
            $span->setAttribute('order.id', (string) $this->orderId);
            $order = Order::findOrFail($this->orderId);
            fulfillOrder($order);
        } catch (\Throwable $e) {
            $span->recordException($e);
            $span->setStatus(StatusCode::STATUS_ERROR);
            throw $e;
        } finally {
            $scope->detach();
            $span->end();
        }
    }
}
```

## Verification

```bash
# Confirm Laravel route spans arrive
tsuga spans search --query "context.service.name:<your-service> span.kind:server" --max-results 5

# Confirm queue job spans arrive
tsuga spans search --query "context.service.name:<your-service> messaging.system:laravel_queue" --max-results 5

# Confirm resource attributes (service.version, deployment.environment.name)
tsuga spans search --query "context.service.name:<your-service>" --max-results 1
```

If no data: `tsuga-debug-no-data` skill.
If spans arrive but queue jobs are missing: verify `ext-opentelemetry` C extension is installed (`php -m | grep opentelemetry`).
