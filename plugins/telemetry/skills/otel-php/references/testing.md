# Telemetry Testing — PHP

## In-Memory Exporter Setup

```php
use OpenTelemetry\SDK\Trace\TracerProvider;
use OpenTelemetry\SDK\Trace\SpanProcessor\SimpleSpanProcessor;
use OpenTelemetry\SDK\Trace\SpanExporter\InMemoryExporter;
use OpenTelemetry\API\Trace\SpanKind;

class TelemetryTestCase extends TestCase
{
    protected InMemoryExporter $spanExporter;
    protected TracerProvider $tracerProvider;

    protected function setUp(): void
    {
        $this->spanExporter = new InMemoryExporter();
        $this->tracerProvider = new TracerProvider(
            new SimpleSpanProcessor($this->spanExporter)
        );
        \OpenTelemetry\API\Globals::registerInitializer(function($configurator) {
            return $configurator->withTracerProvider($this->tracerProvider);
        });
    }

    protected function getFinishedSpans(): array
    {
        return $this->spanExporter->getSpans();
    }
}
```

## Span Assertions

```php
class OrderServiceTest extends TelemetryTestCase
{
    public function testCreatesServerRootSpan(): void
    {
        $this->orderService->createOrder(['item' => 'widget', 'quantity' => 2]);

        $spans = $this->getFinishedSpans();
        $this->assertNotEmpty($spans);

        $rootSpans = array_filter($spans, fn($s) => !$s->getParentContext()->isValid());
        $this->assertCount(1, $rootSpans, 'Expected 1 root span');

        $root = array_values($rootSpans)[0];
        $this->assertSame('POST /orders', $root->getName());
        $this->assertSame(SpanKind::KIND_SERVER, $root->getKind());
    }

    public function testNoOrphanClientSpans(): void
    {
        $this->orderService->createOrder(['item' => 'widget']);

        $orphans = array_filter($this->getFinishedSpans(), fn($s) =>
            in_array($s->getKind(), [SpanKind::KIND_CLIENT, SpanKind::KIND_PRODUCER])
            && !$s->getParentContext()->isValid()
        );

        $this->assertEmpty($orphans,
            'Found orphan CLIENT/PRODUCER spans: ' . implode(', ', array_map(fn($s) => $s->getName(), $orphans))
        );
    }

    public function testSpanNamesAreTemplates(): void
    {
        $this->orderService->createOrder(['item' => 'widget', 'user_id' => 'user-123']);

        foreach ($this->getFinishedSpans() as $span) {
            $this->assertNotRegExp('/[0-9a-f]{8}-[0-9a-f]{4}/', $span->getName(),
                "Span '{$span->getName()}' contains UUID — use template");
            $this->assertNotRegExp('/\/\d+/', $span->getName(),
                "Span '{$span->getName()}' contains numeric ID — use template");
        }
    }
}
```
