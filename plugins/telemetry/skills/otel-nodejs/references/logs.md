# Logs — Node.js OTel

> **Last verified:** 2026-03-23 | SDK: `@opentelemetry/sdk-node` 0.213.x / `@opentelemetry/api` 1.9.x

> **Development status:** Node.js Logs are Development status — the official Node.js getting started page does not include a logs example. Patterns in this file (log bridge via Winston/pino/bunyan) are valid for trace-ID correlation. OTLP log export via `@opentelemetry/exporter-logs-otlp-http` is also available when the task requires logs at the collector endpoint; validate stability for your use case. The `filelog` receiver (stdout JSON → Collector) is the stable ingestion alternative.

## Path Selection

| Scenario | Path |
|----------|------|
| Using Winston | **Path A** — `@opentelemetry/instrumentation-winston` bridge |
| Using pino | **Path B** — `pino-opentelemetry-transport` or manual mixin |
| Using bunyan | **Path C** — `@opentelemetry/instrumentation-bunyan` bridge |
| No logger, minimal setup | **Path D** — manual `trace_id` injection from active span |

> **No zero-code path:** Unlike the Java agent, Node.js has no auto-injecting agent for log context.
> Every log bridge requires explicit setup in your logger configuration.

## Path A — Winston Bridge

The `@opentelemetry/instrumentation-winston` package auto-injects `trace_id`, `span_id`, and `trace_flags` into Winston log records when a span is active.

```bash
npm install @opentelemetry/instrumentation-winston
```

Register in the `NodeSDK` instrumentations array (before SDK start):

```javascript
// tracing.js
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { WinstonInstrumentation } = require('@opentelemetry/instrumentation-winston');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');

const sdk = new NodeSDK({
  instrumentations: [
    getNodeAutoInstrumentations(),
    new WinstonInstrumentation(),   // adds trace_id, span_id to all log records
  ],
});
sdk.start();
```

Winston logger setup (unchanged from normal usage):

```javascript
const winston = require('winston');

const logger = winston.createLogger({
  level: 'info',
  format: winston.format.json(),
  transports: [new winston.transports.Console()],
});

// When a span is active, log records automatically include trace_id and span_id
logger.info('Processing order', { orderId: 'abc-123' });
// Output: { "level":"info", "message":"Processing order", "orderId":"abc-123",
//           "trace_id":"abc...", "span_id":"def...", "trace_flags":"01" }
```

**BAD — manual format without bridge:**

```javascript
// WRONG — trace_id will never appear without the bridge or manual injection
const logger = winston.createLogger({ format: winston.format.simple() });
logger.info('done');  // no trace_id in output
```

## Path B — pino Bridge

**Option 1: `pino-opentelemetry-transport` (auto-injects trace context):**

```bash
npm install pino-opentelemetry-transport
```

```javascript
const pino = require('pino');

const logger = pino({
  transport: { target: 'pino-opentelemetry-transport' },
});

logger.info({ orderId: 'abc-123' }, 'Processing order');
// trace_id and span_id automatically injected when a span is active
```

**Option 2: Manual mixin (no extra package):**

```javascript
const pino = require('pino');
const { trace } = require('@opentelemetry/api');

const logger = pino({
  mixin() {
    const span = trace.getActiveSpan();
    const ctx = span?.spanContext();
    if (!ctx) return {};
    return {
      trace_id: ctx.traceId,
      span_id: ctx.spanId,
      trace_flags: ctx.traceFlags,
    };
  },
});
```

> **`trace.getActiveSpan()` depends on `AsyncLocalStorageContextManager`**, which is set up
> automatically by `NodeSDK` and `NodeTracerProvider` (requires Node.js `^18.19.0 || >=20.6.0` with SDK 2.0). This is why the SDK
> init file must be loaded before any app code.

## Path C — bunyan Bridge

```bash
npm install @opentelemetry/instrumentation-bunyan
```

```javascript
// tracing.js
const { BunyanInstrumentation } = require('@opentelemetry/instrumentation-bunyan');

const sdk = new NodeSDK({
  instrumentations: [
    getNodeAutoInstrumentations(),
    new BunyanInstrumentation(),
  ],
});
sdk.start();
```

Bunyan logger usage is unchanged — `trace_id` and `span_id` are injected automatically.

## Path D — Manual Injection (No Logger Framework)

Use when you cannot install a bridge package but need trace correlation.

```javascript
const { trace } = require('@opentelemetry/api');

function getTraceContext() {
  const span = trace.getActiveSpan();
  const ctx = span?.spanContext();
  if (!ctx || !ctx.traceId) return {};
  return {
    trace_id: ctx.traceId,
    span_id: ctx.spanId,
    trace_flags: ctx.traceFlags,
  };
}

// Inject manually into each log call
console.log(JSON.stringify({
  level: 'info',
  message: 'Processing order',
  orderId: 'abc-123',
  ...getTraceContext(),
}));
```

## AsyncLocalStorage and Context Propagation

`trace.getActiveSpan()` works via `AsyncLocalStorageContextManager`, which tracks the active span through `async/await`, Promises, and callbacks automatically (requires Node.js `^18.19.0 || >=20.6.0` with SDK 2.0).

**Context is propagated correctly through:**
- `async/await`
- `Promise.then/catch/finally`
- `setTimeout` / `setInterval` (when called from within an active span)
- `startActiveSpan` callbacks

**Context is NOT propagated through:**
- `EventEmitter` listeners registered before the span was started
- Fire-and-forget `setImmediate` / `setTimeout` calls made outside an active span

**GOOD — span active when log is called:**

```javascript
tracer.startActiveSpan('process order', async (span) => {
  // trace.getActiveSpan() returns this span here
  logger.info('Starting order processing');   // trace_id injected
  await doWork();
  span.end();
});
```

**BAD — span not active when log is called:**

```javascript
const span = tracer.startSpan('process order');  // NOT set as active context
logger.info('Processing');  // trace_id MISSING — no active span
span.end();
```

## Verification

```bash
# Confirm logs arrive with trace correlation
tsuga logs search --query "context.service.name:<your-service> trace_id:*" --max-results 3

# If trace_id is present but spans are not linking
tsuga spans search --query "context.service.name:<your-service> traceId:<trace-id-from-log>"
```

If verification fails:
- `trace_id` absent from logs → check bridge setup or use `tsuga-debug-missing-trace-propagation`
- Zero log results → `tsuga-debug-no-data`
