# Span Naming, Kind, and Status Rules — Node.js

> **Last verified:** 2026-03-23 | SDK: `@opentelemetry/sdk-node` 0.213.x / `@opentelemetry/api` 1.9.x
>
> See also: `otel-semantic-conventions` skill for attribute naming; `otel-reference.md` for instrument types.

## Span Naming

**Pattern:** `{verb} {object}` in sentence case. Low-cardinality — no IDs, no raw paths.

| BAD | GOOD | Why |
|-----|------|-----|
| `` `GET /users/${userId}/orders` `` | `GET /users/{id}/orders` | Template literals create unbounded cardinality |
| `processOrder` | `process order` | Space-separated verb-object |
| `dbQuery` | `SELECT orders` | Include operation and object |

```javascript
// BAD
const span = tracer.startSpan(`GET /users/${userId}/orders`);

// GOOD
const span = tracer.startSpan('GET /users/{id}/orders');
span.setAttribute('user.id', userId);  // ID goes on attribute
```

## Span Kind Decision Tree

| Scenario | SpanKind |
|----------|----------|
| Inbound HTTP/gRPC handler | `SpanKind.SERVER` |
| Outbound HTTP, gRPC, DB call | `SpanKind.CLIENT` |
| Publishing to Kafka/SQS | `SpanKind.PRODUCER` |
| Consuming from queue | `SpanKind.CONSUMER` |
| Local function (no I/O) | `SpanKind.INTERNAL` |

```javascript
const { SpanKind } = require('@opentelemetry/api');

const span = tracer.startSpan('POST /orders', { kind: SpanKind.SERVER });
const span = tracer.startSpan('GET products-service', { kind: SpanKind.CLIENT });
```

## HTTP Status → Span Status Mapping

| Span Kind | HTTP 4xx | HTTP 5xx |
|-----------|----------|----------|
| SERVER | **UNSET** (server did its job) | ERROR |
| CLIENT | **ERROR** (call failed) | ERROR |

```javascript
const { SpanStatusCode } = require('@opentelemetry/api');

// Server span: 400 is NOT an error
if (statusCode >= 500) {
    span.setStatus({ code: SpanStatusCode.ERROR, message: 'Internal server error' });
}
// 4xx: leave status as default UNSET

// Client span: 4xx IS an error
if (statusCode >= 400) {
    span.setStatus({ code: SpanStatusCode.ERROR, message: `HTTP ${statusCode}` });
}
```

## Headless Operations Pattern

```javascript
const { context, ROOT_CONTEXT } = require('@opentelemetry/api');

// BAD: cron callback creates child spans with no parent
cron.schedule('0 0 * * *', () => {
    const span = tracer.startSpan('query-stale-records');  // Orphan!
});

// GOOD: create SERVER root span as explicit context
cron.schedule('0 0 * * *', () => {
    const rootSpan = tracer.startSpan('nightly-cleanup', {
        kind: SpanKind.SERVER,
        attributes: { 'task.name': 'nightly-cleanup', 'task.trigger': 'cron' },
        root: true,  // Explicitly marks this as a root span
    });
    context.with(trace.setSpan(ROOT_CONTEXT, rootSpan), () => {
        const child = tracer.startSpan('query-stale-records');
        // work
        child.end();
    });
    rootSpan.end();
});
```

## Span Hygiene Rules

- **< 10 INTERNAL spans per trace**
- **< 20 spans under 5ms**
- **No orphan spans** — every span except root must have a parent
- **Root spans cannot be CLIENT or PRODUCER**
- **Error spans must include a message** — `{ code: SpanStatusCode.ERROR, message: 'description' }`

## Span Budget

| Signal | Per-request budget | Notes |
|--------|--------------------|-------|
| Incoming HTTP request | ✅ Always | Auto-instrumentation covers this |
| Outgoing HTTP / gRPC call | ✅ Always | Auto-instrumentation covers this |
| DB query | ✅ Always | Auto-instrumentation covers pg, mysql, redis, etc. |
| External service call | ✅ Always | — |
| Business transaction (`order.place`, `payment.charge`) | ✅ Yes | Manual span via `startActiveSpan` |
| Internal helper function | ❌ Skip | Unless measurably slow or failure-prone |
| Utility called thousands of times per request | ❌ Skip | Creates noise; use metric instead |
| Loop iteration (per-item span in a batch) | ⚠️ Only if needed | Confirm sampling is in place first |

Anti-pattern: instrumenting every function. The span budget goal is minimum spans needed to diagnose failures and measure latency at service boundaries.

## Workflow Boundaries

**Rule:** Same user operation across services → continue the trace (propagate W3C `traceparent`). Separate operations, separate queue deliveries, or separate scheduled jobs → new root span.

Never propagate a parent context from one unrelated job into another.

### Continue the trace (outbound HTTP call)

```javascript
const { propagation, context } = require('@opentelemetry/api');

// Auto-instrumentation handles this for standard http/https and fetch.
// For a custom HTTP client, inject manually:
const headers = {};
propagation.inject(context.active(), headers);
// headers now contains: { traceparent: '00-<traceId>-<spanId>-01' }
await customHttpClient.request(url, { headers });
```

### New root span (scheduled job or batch)

```javascript
const { trace, context, SpanKind, ROOT_CONTEXT } = require('@opentelemetry/api');
const tracer = trace.getTracer('my-service');

// context.with(ROOT_CONTEXT, ...) ensures no parent context is inherited
context.with(ROOT_CONTEXT, () => {
  tracer.startActiveSpan(
    'nightly-cleanup',
    {
      kind: SpanKind.SERVER,
      attributes: { 'task.name': 'nightly-cleanup', 'task.trigger': 'cron' },
    },
    (span) => {
      doWork();
      span.end();
    }
  );
});
```

### Related but not parent-child (async queue consumer)

```javascript
const { trace, context, SpanKind } = require('@opentelemetry/api');

// Extract producer context from message headers, then create a linked root span
const producerContext = propagation.extract(context.active(), messageHeaders);
const producerSpanContext = trace.getSpanContext(producerContext);

tracer.startActiveSpan(
  'process order',
  {
    kind: SpanKind.CONSUMER,
    links: producerSpanContext ? [{ context: producerSpanContext }] : [],
  },
  context.active(),  // NOT producerContext — span is a new root
  (span) => {
    doWork();
    span.end();
  }
);
```

> **→** `references/async-messaging.md` — full Kafka, AMQP, and SQS patterns with semconv.
