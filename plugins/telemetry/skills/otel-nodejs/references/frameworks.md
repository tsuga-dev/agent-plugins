# Framework-Specific Recipes — Node.js

## Express

Auto-instrumentation via `@opentelemetry/instrumentation-express` (bundled in `auto-instrumentations-node`) creates spans for each route handler and middleware, automatically capturing HTTP method, route template, and status code as span attributes.

```javascript
// otel.js — load BEFORE express
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { resourceFromAttributes } = require('@opentelemetry/resources');
const { ATTR_SERVICE_NAME } = require('@opentelemetry/semantic-conventions');

const sdk = new NodeSDK({
  resource: resourceFromAttributes({ [ATTR_SERVICE_NAME]: 'express-service' }),
  traceExporter: new OTLPTraceExporter(),
  instrumentations: [getNodeAutoInstrumentations()],
});
sdk.start();
```

Add manual child spans inside route handlers when you need to trace business logic or database calls that aren't covered by a library instrumentation — for example, a raw `pg` query or a custom validation step that would otherwise be invisible in the trace.

```javascript
// app.js
const express = require('express');
const { trace, SpanStatusCode } = require('@opentelemetry/api');

const app = express();
app.use(express.json());

// Auto-instrumentation creates spans for this route automatically
app.get('/users/:id', async (req, res) => {
  const tracer = trace.getTracer('express-service');

  // Add a child span for the DB call
  await tracer.startActiveSpan('db.getUser', async (span) => {
    try {
      span.setAttribute('db.user.id', req.params.id);
      const user = await getUserFromDb(req.params.id);
      span.end();
      res.json(user);
    } catch (err) {
      span.recordException(err);
      span.setStatus({ code: SpanStatusCode.ERROR });
      span.end();
      res.status(500).json({ error: 'internal server error' });
    }
  });
});

// Exclude health endpoints from tracing
app.get('/health', (req, res) => res.sendStatus(200));
```

Health checks and metrics scrape endpoints fire continuously in production but carry no diagnostic value. Excluding them reduces trace volume and keeps your signal-to-noise ratio high, making it easier to spot real problems in your trace data.

Configure the HTTP instrumentation to ignore health checks:

```javascript
getNodeAutoInstrumentations({
  '@opentelemetry/instrumentation-http': {
    ignoreIncomingRequestHook: (req) =>
      req.url === '/health' || req.url === '/metrics',
  },
})
```

## Fastify

`@opentelemetry/instrumentation-fastify` is **deprecated**. The current integration is `@fastify/otel`. If your codebase still uses the old package, remove it and switch to `@fastify/otel` — the old package no longer receives updates and may not work correctly with recent versions of Fastify or the OTel SDK.

```bash
npm install @fastify/otel @opentelemetry/sdk-node @opentelemetry/exporter-trace-otlp-grpc
```

```javascript
// otel.js — load first
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { resourceFromAttributes } = require('@opentelemetry/resources');
const { ATTR_SERVICE_NAME } = require('@opentelemetry/semantic-conventions');

const sdk = new NodeSDK({
  resource: resourceFromAttributes({ [ATTR_SERVICE_NAME]: 'fastify-service' }),
  traceExporter: new OTLPTraceExporter(),
  // Do NOT include getNodeAutoInstrumentations if using @fastify/otel — it handles Fastify
});
sdk.start();
```

```javascript
// app.js
const Fastify = require('fastify');
const { FastifyOtelInstrumentation } = require('@fastify/otel');

const app = Fastify({ logger: true });

// Create instrumentation instance — service name comes from OTEL_SERVICE_NAME or NodeSDK resource, not from this constructor
const fastifyOtelInstrumentation = new FastifyOtelInstrumentation({
  // Ignore specific paths (glob string or function)
  ignorePaths: ['/health', '/metrics'],
});

// Register the plugin BEFORE routes
await app.register(fastifyOtelInstrumentation.plugin());

app.get('/users/:id', async (request, reply) => {
  const { trace, context } = require('@opentelemetry/api');
  const tracer = trace.getTracer('fastify-service');

  return tracer.startActiveSpan('db.getUser', async (span) => {
    try {
      span.setAttribute('user.id', request.params.id);
      const user = await getUserFromDb(request.params.id);
      span.end();
      return user;
    } catch (err) {
      span.recordException(err);
      span.end();
      throw err;
    }
  });
});

await app.listen({ port: 3000 });
```

## NestJS

NestJS runs on top of Express or Fastify. Use `@opentelemetry/instrumentation-http` + `@opentelemetry/instrumentation-express` (bundled in `auto-instrumentations-node`) for automatic route tracing.

```bash
npm install @opentelemetry/sdk-node @opentelemetry/auto-instrumentations-node \
  @opentelemetry/exporter-trace-otlp-grpc
```

```javascript
// otel.js — load via NODE_OPTIONS before NestJS bootstraps
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { resourceFromAttributes } = require('@opentelemetry/resources');
const { ATTR_SERVICE_NAME } = require('@opentelemetry/semantic-conventions');

const sdk = new NodeSDK({
  resource: resourceFromAttributes({ [ATTR_SERVICE_NAME]: 'nest-service' }),
  traceExporter: new OTLPTraceExporter(),
  instrumentations: [getNodeAutoInstrumentations()],
});
sdk.start();
```

```bash
# package.json start script
NODE_OPTIONS='--require ./otel.js' nest start
```

NestJS auto-instrumentation via `getNodeAutoInstrumentations()` applies uniformly across the whole application, which is appropriate when you want consistent tracing without per-service configuration. For finer control — for instance, when you want a specific service to add domain-specific attributes or trace only certain methods — inject the tracer through a custom provider so each service manages its own spans independently.

For manual spans in NestJS services, inject the tracer via a custom provider:

```typescript
// tracing.service.ts
import { Injectable } from '@nestjs/common';
import { trace, Tracer } from '@opentelemetry/api';

@Injectable()
export class TracingService {
  private readonly tracer: Tracer;

  constructor() {
    this.tracer = trace.getTracer('nest-service');
  }

  getTracer(): Tracer {
    return this.tracer;
  }
}
```

## Koa

Auto-instrumented via `@opentelemetry/instrumentation-koa` (bundled in `auto-instrumentations-node`).

```bash
npm install koa @koa/router @opentelemetry/sdk-node \
  @opentelemetry/auto-instrumentations-node \
  @opentelemetry/exporter-trace-otlp-grpc
```

```javascript
// otel.js
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { resourceFromAttributes } = require('@opentelemetry/resources');
const { ATTR_SERVICE_NAME } = require('@opentelemetry/semantic-conventions');

const sdk = new NodeSDK({
  resource: resourceFromAttributes({ [ATTR_SERVICE_NAME]: 'koa-service' }),
  traceExporter: new OTLPTraceExporter(),
  instrumentations: [getNodeAutoInstrumentations()],
});
sdk.start();
```

```javascript
// app.js
const Koa = require('koa');
const Router = require('@koa/router');
const { trace, SpanStatusCode } = require('@opentelemetry/api');

const app = new Koa();
const router = new Router();

// Custom error-recording middleware
app.use(async (ctx, next) => {
  try {
    await next();
  } catch (err) {
    const span = trace.getActiveSpan();
    if (span) {
      span.recordException(err);
      span.setStatus({ code: SpanStatusCode.ERROR, message: err.message });
    }
    ctx.status = err.status || 500;
    ctx.body = { error: err.message };
  }
});

router.get('/users/:id', async (ctx) => {
  const tracer = trace.getTracer('koa-service');
  await tracer.startActiveSpan('db.getUser', async (span) => {
    span.setAttribute('user.id', ctx.params.id);
    ctx.body = await getUserFromDb(ctx.params.id);
    span.end();
  });
});

app.use(router.routes());
app.listen(3000);
```

## Span Naming Best Practices

For all frameworks, follow these naming conventions for manual spans:

| Operation | Span Name |
|---|---|
| Database query | `db.<operation>` (e.g., `db.getUser`) |
| Cache operation | `cache.<operation>` (e.g., `cache.set`) |
| External API call | `http.call.<service>` |
| Background job | `job.<name>` |
| Business logic | `<domain>.<action>` (e.g., `order.validate`) |

Keep span names low-cardinality — avoid including IDs, user names, or dynamic values in the name; use attributes instead.

## Lifecycle Logging

Structured log events correlated with OTel trace context.

```typescript
import { context, trace } from '@opentelemetry/api';

// Inject OTel trace context into every log record
function withTraceContext(fields: Record<string, unknown> = {}) {
    const span = trace.getActiveSpan();
    const ctx = span?.spanContext();
    if (ctx) {
        return {
            ...fields,
            trace_id: ctx.traceId,
            span_id: ctx.spanId,
        };
    }
    return fields;
}

// Using pino (recommended for production Node.js)
import pino from 'pino';
const logger = pino({ base: { service: process.env.OTEL_SERVICE_NAME } });

// --- Service startup ---
function logStartup() {
    logger.info(withTraceContext({
        version: process.env.APP_VERSION ?? 'unknown',
        environment: process.env.NODE_ENV ?? 'unknown',
        otlp_endpoint: process.env.OTEL_EXPORTER_OTLP_ENDPOINT ?? 'not set',
    }), 'service starting');
}

// --- Request lifecycle (Express middleware) ---
app.use((req, res, next) => {
    logger.info(withTraceContext({ method: req.method, path: req.path }), 'request received');
    res.on('finish', () => {
        logger.info(withTraceContext({
            method: req.method,
            path: req.path,
            status: res.statusCode,
        }), 'request completed');
    });
    next();
});

// --- Graceful shutdown ---
process.on('SIGTERM', async () => {
    logger.info(withTraceContext(), 'service shutting down');
    await sdk.shutdown();
    logger.info(withTraceContext(), 'otel sdk shut down');
    process.exit(0);
});
```

> The JS Logs SDK (`@opentelemetry/sdk-logs`) is still experimental/development status. Use the pattern above (inject trace context into your existing logger) for production.
