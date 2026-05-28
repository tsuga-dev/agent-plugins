# PHP Framework Recipes — Symfony

> **Last verified:** 2026-03-23 | SDK: `open-telemetry/opentelemetry-php` 1.13.0 | exporter-otlp 1.4.0

## Resource Initialization — GOOD vs BAD

```php
// BAD — service.name hardcoded; cannot change without a deploy
$resource = ResourceInfo::create(Attributes::create([
    ResourceAttributes::SERVICE_NAME => $_ENV['OTEL_SERVICE_NAME'] ?? 'symfony-app',
    'deployment.environment.name'    => $_ENV['APP_ENV'] ?? 'production',
]));

// GOOD — ResourceInfoFactory::defaultResource() reads OTEL_SERVICE_NAME automatically
use OpenTelemetry\SDK\Resource\ResourceInfoFactory;

$resource = ResourceInfoFactory::defaultResource()->merge(
    ResourceInfo::create(Attributes::create([
        ResourceAttributes::SERVICE_VERSION => $_ENV['APP_VERSION'] ?? '0.0.0',
    ]))
);
```

```bash
composer require \
    open-telemetry/sdk:^1.13 \
    open-telemetry/exporter-otlp:^1.4 \
    open-telemetry/opentelemetry-auto-symfony \
    php-http/guzzle7-adapter
```

**Bundle / kernel event subscriber:**

```php
<?php
// src/EventSubscriber/OpenTelemetrySubscriber.php

namespace App\EventSubscriber;

use OpenTelemetry\API\Globals;
use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;
use OpenTelemetry\Contrib\Otlp\SpanExporter;
use OpenTelemetry\SDK\Common\Attribute\Attributes;
use OpenTelemetry\SDK\Resource\ResourceInfo;
use OpenTelemetry\SDK\Resource\ResourceInfoFactory;
use OpenTelemetry\SDK\Sdk;
use OpenTelemetry\SDK\Trace\SpanProcessor\BatchSpanProcessor;
use OpenTelemetry\SDK\Trace\TracerProvider;
// ResourceAttributes is deprecated; prefer OpenTelemetry\SemConv\Attributes\ServiceAttributes
use OpenTelemetry\SemConv\ResourceAttributes;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpKernel\KernelEvents;
use Symfony\Component\HttpKernel\Event\RequestEvent;

class OpenTelemetrySubscriber implements EventSubscriberInterface
{
    private static bool $initialized = false;

    public static function getSubscribedEvents(): array
    {
        return [KernelEvents::REQUEST => ['onKernelRequest', 9999]];
    }

    public function onKernelRequest(RequestEvent $event): void
    {
        if (self::$initialized || !$event->isMainRequest()) return;
        self::$initialized = true;

        // GOOD — reads OTEL_SERVICE_NAME from env automatically
        $resource = ResourceInfoFactory::defaultResource()->merge(
            ResourceInfo::create(Attributes::create([
                ResourceAttributes::SERVICE_VERSION => $_ENV['APP_VERSION'] ?? '0.0.0',
            ]))
        );

        $endpoint  = $_ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] ?? 'http://localhost:4318';
        $transport = (new OtlpHttpTransportFactory())->create(
            $endpoint . '/v1/traces', 'application/x-protobuf'
        );

        $tracerProvider = TracerProvider::builder()
            ->addSpanProcessor(new BatchSpanProcessor(new SpanExporter($transport)))
            ->setResource($resource)
            ->build();

        Sdk::builder()
            ->setTracerProvider($tracerProvider)
            ->setAutoShutdown(true)
            ->buildAndRegisterGlobal();
    }
}
```

**Symfony Controller:**

```php
<?php

namespace App\Controller;

use OpenTelemetry\API\Globals;
use OpenTelemetry\API\Trace\StatusCode;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\Routing\Attribute\Route;

class UserController extends AbstractController
{
    #[Route('/users/{id}', methods: ['GET'])]
    public function getUser(int $id): JsonResponse
    {
        $tracer = Globals::tracerProvider()->getTracer('symfony-app');

        $span  = $tracer->spanBuilder('db.get_user')
            ->setAttribute('user.id', (string) $id)
            ->startSpan();
        $scope = $span->activate();
        try {
            $user = $this->userRepository->find($id);
            if (!$user) {
                $span->setStatus(StatusCode::STATUS_ERROR, 'not found');
                return $this->json(['error' => 'not found'], 404);
            }
            return $this->json($user);
        } finally {
            $scope->detach();
            $span->end();
        }
    }
}
```

## Symfony Messenger Integration

Symfony Messenger spans are created automatically by `opentelemetry-auto-symfony`. For manual instrumentation of message handlers:

```php
<?php

namespace App\MessageHandler;

use OpenTelemetry\API\Globals;
use OpenTelemetry\API\Trace\StatusCode;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

#[AsMessageHandler]
class ProcessOrderHandler
{
    public function __invoke(ProcessOrder $message): void
    {
        $tracer = Globals::tracerProvider()->getTracer('symfony-app');
        $span  = $tracer->spanBuilder('order.process')->startSpan();
        $scope = $span->activate();
        try {
            $span->setAttribute('order.id', (string) $message->orderId);
            // handle message
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
```

## Verification

```bash
# Confirm Symfony controller spans arrive
tsuga spans search --query "context.service.name:<your-service> span.kind:server" --max-results 5

# Confirm Messenger handler spans arrive
tsuga spans search --query "context.service.name:<your-service> span.name:order.process" --max-results 5

# Confirm resource attributes (service.version, deployment.environment.name)
tsuga spans search --query "context.service.name:<your-service>" --max-results 1
```

If no data: `tsuga-debug-no-data` skill.
If spans arrive but Messenger spans are missing: verify `ext-opentelemetry` C extension is installed (`php -m | grep opentelemetry`).
