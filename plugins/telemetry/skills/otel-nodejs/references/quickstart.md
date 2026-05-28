# Quick Start — Node.js OTel

> **Last verified:** 2026-03-23 | SDK: `@opentelemetry/sdk-node` 0.213.x (experimental) / `@opentelemetry/api` 1.9.x / stable exporters `@opentelemetry/exporter-*` 2.6.x

> Run `node --version` — Node.js 18.19+ required for SDK 0.213.x. If below 18, use SDK ≤ 0.50.x (Node 16) or stop and report if below 16.

## Package Setup

```bash
npm install \
  @opentelemetry/api@^1.9.0 \
  @opentelemetry/sdk-node@~0.213.0 \
  @opentelemetry/auto-instrumentations-node \
  @opentelemetry/exporter-trace-otlp-http@~2.6.0 \
  @opentelemetry/exporter-metrics-otlp-http@~2.6.0
```

> **JS SDK 2.x versioning split:** Stable exporter/API packages (`@opentelemetry/exporter-*`, `@opentelemetry/api`) are versioned `≥2.0.0`. The `NodeSDK` wrapper (`@opentelemetry/sdk-node`) follows the experimental train at `≥0.200.0`. Both are production-ready — the version numbers reflect two separate release trains. Install matching minor versions within each train.

For gRPC transport instead of HTTP (optional):

```bash
npm install \
  @opentelemetry/exporter-trace-otlp-grpc@~2.6.0 \
  @opentelemetry/exporter-metrics-otlp-grpc@~2.6.0
```

> **Optional — Logs OTLP Export (Development status):** Node.js logs are Development status — the official getting started page omits a logs example. If you need OTLP log export (experimental):
> ```bash
> npm install @opentelemetry/exporter-logs-otlp-http@~2.6.0
> ```
> Prefer Winston/pino/bunyan bridge for trace-ID correlation instead — see `references/logs.md`.

## SDK Initialization — NodeSDK (Recommended)

Create `tracing.js` (or `otel.js`) in the project root. This file must be loaded **before** any application or framework code — it patches Node.js built-in modules and third-party libraries at load time.

```javascript
// tracing.js — loaded BEFORE app code via --require or NODE_OPTIONS
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-http');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');

// NodeSDK reads OTEL_SERVICE_NAME automatically via defaultResource().
// OTLPTraceExporter() zero-arg reads OTEL_EXPORTER_OTLP_ENDPOINT
// (default: http://localhost:4318/v1/traces — HTTP/JSON).
const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter(),
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter(),
  }),
  instrumentations: [getNodeAutoInstrumentations()],
});

sdk.start();

// CRITICAL: sdk.shutdown() returns a Promise — must be awaited.
// Calling process.exit(0) before await drops in-flight spans.
process.on('SIGTERM', async () => {
  try {
    await sdk.shutdown();
  } catch (err) {
    console.error('OTel shutdown error', err);
  }
  process.exit(0);
});
```

**GOOD — SDK loaded via `--require` flag:**

```bash
node --require ./tracing.js app.js
```

**GOOD — SDK loaded via `NODE_OPTIONS` (works with any runner, Docker, PM2):**

```bash
NODE_OPTIONS='--require ./tracing.js' node app.js
```

**BAD — SDK imported inside app.js after other imports:**

```javascript
// WRONG — http and express already loaded; auto-instrumentation patches are missed
const express = require('express');
const { NodeSDK } = require('@opentelemetry/sdk-node');
```

## ESM Projects

Use `--import` instead of `--require` for ES Modules:

```bash
node --import ./tracing.js app.js
# or
NODE_OPTIONS='--import ./tracing.js' node app.js
```

The init file must use `import` syntax and be a `.mjs` file or have `"type": "module"` in `package.json`.

## Manual Provider Setup (Without NodeSDK)

Use when you need fine-grained control over processors, multiple exporters, or are building a library that must not set global providers.

```javascript
// tracing-manual.js
const { NodeTracerProvider, BatchSpanProcessor } = require('@opentelemetry/sdk-trace-node');
const { MeterProvider, PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-http');
const { trace, metrics } = require('@opentelemetry/api');
const { defaultResource } = require('@opentelemetry/resources');

// defaultResource() reads OTEL_SERVICE_NAME and OTEL_RESOURCE_ATTRIBUTES automatically.
// Do NOT hardcode 'service.name' — let the env var control it.
const resource = defaultResource();

const tracerProvider = new NodeTracerProvider({
  resource,
  spanProcessors: [new BatchSpanProcessor(new OTLPTraceExporter())],
});
trace.setGlobalTracerProvider(tracerProvider);

const meterProvider = new MeterProvider({
  resource,
  readers: [new PeriodicExportingMetricReader({ exporter: new OTLPMetricExporter() })],
});
metrics.setGlobalMeterProvider(meterProvider);

process.on('SIGTERM', async () => {
  await tracerProvider.shutdown();
  await meterProvider.shutdown();
  process.exit(0);
});
```

> **Note:** `BasicTracerProvider` from `@opentelemetry/sdk-trace-base` does NOT include Node.js async context propagation (`AsyncLocalStorageContextManager`). Always use `NodeTracerProvider` from `@opentelemetry/sdk-trace-node` in Node.js services.

## OTLP Exporter Configuration

**HTTP/JSON (default, port 4318):**

```javascript
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
// Zero-arg reads OTEL_EXPORTER_OTLP_ENDPOINT. SDK appends /v1/traces automatically.
// Do NOT pass url: unless overriding for a specific reason.
// NOTE: This package uses HTTP/JSON encoding. For HTTP/protobuf, use
// @opentelemetry/exporter-trace-otlp-proto instead.
const exporter = new OTLPTraceExporter();
```

**gRPC (port 4317):**

```javascript
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
// Zero-arg reads OTEL_EXPORTER_OTLP_ENDPOINT. No path suffix appended.
const exporter = new OTLPTraceExporter();
```

**BAD — hardcoded endpoint:**

```javascript
// WRONG — endpoint breaks in staging, production, and CI environments
const exporter = new OTLPTraceExporter({ url: 'http://localhost:4318/v1/traces' });
```

## Required Environment Variables

```bash
# Minimum required — see references/resource-attributes.md to resolve the correct service name
OTEL_SERVICE_NAME=my-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318   # HTTP default port

# Recommended
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production,service.version=1.4.2
# WARNING: One invalid k=v pair in OTEL_RESOURCE_ATTRIBUTES silences the entire variable.
# Validate each entry — no spaces around '=', no special chars in key names.

# gRPC opt-in (Collector gRPC receiver on port 4317)
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc

# Ensure the SDK file is loaded before app code
NODE_OPTIONS='--require ./tracing.js'
```

## Post-Deploy Verification

```bash
# Confirm traces arrive
tsuga spans search --query "context.service.name:my-service" --max-results 5

# Confirm logs with trace correlation
tsuga logs search --query "context.service.name:my-service trace_id:*" --max-results 3

# Confirm metrics
tsuga metrics list --filter "service.name=my-service"
```

If no data: `tsuga-debug-no-data` skill.
If traces don't link across services: `tsuga-debug-missing-trace-propagation` skill.
