# Distributed Context Propagation — Node.js

> **Last verified:** 2026-03-23 | SDK: `@opentelemetry/sdk-node` 0.213.x / `@opentelemetry/api` 1.9.x

## Overview

Trace context must be explicitly propagated across service boundaries. The W3C TraceContext headers (`traceparent`, `tracestate`) carry the trace ID and span ID between services. The OpenTelemetry Node.js SDK sets up W3C propagators automatically when using `NodeSDK` or `NodeTracerProvider`.

## Inbound: Server Context Extraction

When using auto-instrumentation (`@opentelemetry/instrumentation-http`), inbound HTTP context extraction is automatic — the instrumentation reads `traceparent` from incoming request headers and sets it as the active context for the request handler.

For manual extraction (e.g., custom transport, non-HTTP protocols):

```javascript
const { propagation, context, trace } = require('@opentelemetry/api');

// In an HTTP handler — extract from incoming headers
function handleRequest(req, res) {
  // req.headers is a plain object: { traceparent: '...', tracestate: '...' }
  const parentCtx = propagation.extract(context.active(), req.headers);

  // Start span as child of the extracted context
  const tracer = trace.getTracer('my-service');
  tracer.startActiveSpan('handle.request', {}, parentCtx, (span) => {
    try {
      doWork();
      span.end();
    } catch (err) {
      span.recordException(err);
      span.end();
      throw err;
    }
  });
}
```

## Outbound: Client Context Injection

When using auto-instrumentation, outbound HTTP calls via `http`/`https` or `fetch` (undici) are automatically instrumented — the SDK injects `traceparent` into outgoing request headers.

For manual injection (e.g., custom HTTP client, raw TCP):

```javascript
const { propagation, context } = require('@opentelemetry/api');
const https = require('https');

function callDownstream(url) {
  const headers = {};
  // Inject current active context into the headers object
  propagation.inject(context.active(), headers);

  // headers now contains: { traceparent: '00-<traceId>-<spanId>-01' }
  const req = https.request(url, { headers }, (res) => { /* handle */ });
  req.end();
}
```

With `node-fetch` or `axios`:

```javascript
const { propagation, context } = require('@opentelemetry/api');
const fetch = require('node-fetch');

async function callService(url) {
  const headers = { 'Content-Type': 'application/json' };
  propagation.inject(context.active(), headers);

  const response = await fetch(url, { headers });
  return response.json();
}
```

> **For message queue propagation (Kafka, AMQP, SQS)** → see `references/async-messaging.md` for span Links, semconv attributes, and auto-instrumentation coverage.

## Anti-Pattern: Do Not Merge Separate Workflows

Creating a child span that links an unrelated job/workflow to an existing trace creates misleading traces. Each independent workflow (e.g., a background job triggered by a queue message) should start a new root span — extract context from the message to create a **link**, not a parent-child relationship.

**Wrong:**
```javascript
// This makes the job appear as a child of the HTTP request that sent the message
tracer.startActiveSpan('process.job', {}, extractedCtx, (span) => { ... });
```

**Correct:**
```javascript
// Link to producer trace for observability, but do not parent it
const link = { context: trace.getSpanContext(extractedCtx) };
tracer.startActiveSpan('process.job', { links: [link] }, (span) => { ... });
```

## Custom Text Map Propagator

Use W3C TraceContext (the default) for all new services. Add B3 via `B3Propagator` only when your service must receive traces from existing Zipkin-instrumented services or legacy Spring Cloud Sleuth deployments. Running both via `CompositePropagator` adds negligible overhead and maintains backward compatibility during migration.

To use a non-standard propagation format (e.g., B3, Jaeger), configure the propagator at SDK init:

```javascript
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { B3Propagator } = require('@opentelemetry/propagator-b3');
const { CompositePropagator, W3CTraceContextPropagator, W3CBaggagePropagator } = require('@opentelemetry/core');

const sdk = new NodeSDK({
  textMapPropagator: new CompositePropagator({
    propagators: [
      new W3CTraceContextPropagator(),
      new W3CBaggagePropagator(),
      new B3Propagator(),  // also accept B3 headers from legacy services
    ],
  }),
  // ...
});
```

## Tsuga Trace Continuity Validation

After instrumenting propagation, verify parent/child linkage across services:

```bash
tsuga spans search --query "context.service.name:<caller-service>" --max-results 5
# Note the traceId from spans
# Then verify callee shows same traceId:
tsuga spans search --query "context.service.name:<callee-service> traceId:<trace-id>"
# parentSpanId on callee spans should match spanId from the caller
```
