# Telemetry Testing — Node.js

## In-Memory Exporter Setup

```javascript
const { NodeTracerProvider } = require('@opentelemetry/sdk-trace-node');
const { InMemorySpanExporter, SimpleSpanProcessor } = require('@opentelemetry/sdk-trace-base');
const { MeterProvider } = require('@opentelemetry/sdk-metrics');
const { TestMetricReader } = require('@opentelemetry/sdk-metrics'); // or InMemoryMetricExporter

function createTestProvider() {
    const exporter = new InMemorySpanExporter();
    const provider = new NodeTracerProvider({
        spanProcessors: [new SimpleSpanProcessor(exporter)],
    });
    provider.register();
    return { exporter, provider };
}
```

## Span Assertions

```javascript
const { SpanKind, SpanStatusCode } = require('@opentelemetry/api');
const assert = require('assert');

describe('OrderService', () => {
    let exporter, provider;

    beforeEach(() => {
        ({ exporter, provider } = createTestProvider());
    });

    afterEach(async () => {
        exporter.reset();
        await provider.shutdown();
    });

    it('creates a SERVER root span', async () => {
        await createOrder({ item: 'widget', quantity: 2 });

        const spans = exporter.getFinishedSpans();
        assert(spans.length > 0, 'Expected at least one span');

        const rootSpans = spans.filter(s => !s.parentSpanId);
        assert.strictEqual(rootSpans.length, 1, `Expected 1 root span, got ${rootSpans.length}`);
        assert.strictEqual(rootSpans[0].name, 'POST /orders');
        assert.strictEqual(rootSpans[0].kind, SpanKind.SERVER);
    });

    it('has no orphan CLIENT/PRODUCER spans', async () => {
        await createOrder({ item: 'widget' });

        const spans = exporter.getFinishedSpans();
        const orphans = spans.filter(s =>
            (s.kind === SpanKind.CLIENT || s.kind === SpanKind.PRODUCER) && !s.parentSpanId
        );
        assert.strictEqual(orphans.length, 0,
            `Found orphan CLIENT/PRODUCER spans: ${orphans.map(s => s.name).join(', ')}`
        );
    });

    it('error spans have status messages', async () => {
        try { await createOrderWithInvalidData({}); } catch (_) {}

        const errorSpans = exporter.getFinishedSpans()
            .filter(s => s.status.code === SpanStatusCode.ERROR);

        for (const span of errorSpans) {
            assert(span.status.message, `ERROR span '${span.name}' has no status message`);
        }
    });

    it('span names are low-cardinality templates', async () => {
        await createOrder({ item: 'widget', userId: 'user-123' });

        const uuidPattern = /[0-9a-f]{8}-[0-9a-f]{4}/;
        const numericIdPattern = /\/\d+/;

        for (const span of exporter.getFinishedSpans()) {
            assert(!uuidPattern.test(span.name), `Span '${span.name}' contains UUID`);
            assert(!numericIdPattern.test(span.name), `Span '${span.name}' contains numeric ID`);
        }
    });
});
```
