# Auto-Instrumentation — Node.js

## Overview

The `@opentelemetry/auto-instrumentations-node` package bundles all maintained auto-instrumentation plugins for Node.js. When enabled, it hooks into Node.js module loading to patch supported libraries at require-time — zero manual span creation needed for covered libraries.

## Installation

```bash
npm install @opentelemetry/auto-instrumentations-node
```

This package is a meta-package. It pulls in individual instrumentation packages for HTTP, gRPC, Express, Fastify (legacy), Koa, database drivers, messaging clients, and more.

## Setup via NodeSDK (recommended)

```javascript
// otel.js
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { resourceFromAttributes } = require('@opentelemetry/resources');
const { ATTR_SERVICE_NAME, ATTR_SERVICE_VERSION } = require('@opentelemetry/semantic-conventions');

const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: process.env.OTEL_SERVICE_NAME || 'my-service',
    [ATTR_SERVICE_VERSION]: process.env.npm_package_version || '1.0.0',
  }),
  traceExporter: new OTLPTraceExporter(),
  instrumentations: [getNodeAutoInstrumentations()],
});

sdk.start();

process.on('SIGTERM', async () => {
  await sdk.shutdown();
  process.exit(0);
});
```

Load it before any app code:

```bash
node --require ./otel.js app.js
# or
NODE_OPTIONS='--require ./otel.js' node app.js
```

## Selectively Enabling/Disabling Instrumentations

Pass a configuration object to `getNodeAutoInstrumentations` to tune what gets patched:

```javascript
getNodeAutoInstrumentations({
  // Disable fs instrumentation (high volume, low signal)
  '@opentelemetry/instrumentation-fs': { enabled: false },

  // Configure HTTP instrumentation
  '@opentelemetry/instrumentation-http': {
    enabled: true,
    // Ignore health-check endpoints
    ignoreIncomingRequestHook: (req) => req.url === '/health',
    // Capture request/response body size
    requestHook: (span, req) => {
      span.setAttribute('http.request.body.size', req.headers['content-length'] || 0);
    },
  },

  // Configure gRPC
  '@opentelemetry/instrumentation-grpc': { enabled: true },
})
```

## What Gets Covered Automatically

| Library / Category | Package |
|---|---|
| HTTP (inbound + outbound) | `@opentelemetry/instrumentation-http` |
| Express | `@opentelemetry/instrumentation-express` |
| Koa | `@opentelemetry/instrumentation-koa` |
| Hapi | `@opentelemetry/instrumentation-hapi` |
| NestJS (via HTTP) | covered by `instrumentation-http` + `instrumentation-express` |
| gRPC | `@opentelemetry/instrumentation-grpc` |
| MongoDB | `@opentelemetry/instrumentation-mongodb` |
| PostgreSQL (pg) | `@opentelemetry/instrumentation-pg` |
| MySQL / MySQL2 | `@opentelemetry/instrumentation-mysql` / `mysql2` |
| Redis | `@opentelemetry/instrumentation-redis` / `redis-4` |
| AWS SDK | `@opentelemetry/instrumentation-aws-sdk` |
| GraphQL | `@opentelemetry/instrumentation-graphql` |
| Kafka.js | `@opentelemetry/instrumentation-kafkajs` |
| Undici (Node.js fetch) | `@opentelemetry/instrumentation-undici` |
| Winston | `@opentelemetry/instrumentation-winston` |
| Pino | `@opentelemetry/instrumentation-pino` |
| Bunyan | `@opentelemetry/instrumentation-bunyan` |

> **Fastify note:** `@opentelemetry/instrumentation-fastify` is deprecated. Use `@fastify/otel` instead — see `references/frameworks.md`.

## What Needs Manual Instrumentation

Auto-instrumentation does NOT cover:

- Business-logic spans (e.g., "user.checkout", "order.validate") — these must use `tracer.startActiveSpan()`
- Background jobs / cron tasks — no incoming HTTP request to hook into
- Queue consumers (SQS, RabbitMQ) — context extraction from message attributes must be done manually
- Custom protocols / WebSockets — no HTTP hook to patch
- Third-party SDKs that make HTTP calls internally (traced at HTTP layer only, not with semantic detail)

## Zero-Code Auto-Instrumentation (env-only)

For containerized deployments, you can use the `@opentelemetry/auto-instrumentations-node` as a standalone injector:

```bash
npm install --save-dev @opentelemetry/auto-instrumentations-node
node --require @opentelemetry/auto-instrumentations-node/register app.js
```

Configure via environment:

```bash
OTEL_SERVICE_NAME=my-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://collector:4317
OTEL_NODE_ENABLED_INSTRUMENTATIONS=http,express,pg
OTEL_NODE_DISABLED_INSTRUMENTATIONS=fs
```

## ESM Support

Node.js ES Modules require `--import` (not `--require`) and a loader hook:

```bash
node --import ./otel.js app.mjs
```

For ESM, use the `--experimental-loader` approach if `--import` does not patch module loading in your Node.js version (< 20.6). Some instrumentations have limited ESM support — check individual package READMEs.

## Verifying Auto-Instrumentation Is Active

After starting your service, make an HTTP request and check:

```bash
tsuga spans search --query "context.service.name:my-service" --max-results 5
```

Look for span names like `GET /your-route`, `pg.query`, `redis-cmd` — these confirm auto-instrumentation is firing.
