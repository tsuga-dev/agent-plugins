# Endpoint, Protocol, and Troubleshooting — Node.js

> **Last verified:** 2026-03-23 | SDK: `@opentelemetry/sdk-node` 0.213.x / `@opentelemetry/api` 1.9.x

## OTLP Protocol Reference

| Protocol | Port | Path auto-appended by SDK? | SDK package |
|---|---|---|---|
| OTLP/HTTP JSON | 4318 | Yes (`/v1/traces`, `/v1/metrics`, `/v1/logs`) | `@opentelemetry/exporter-trace-otlp-http` |
| OTLP/gRPC | 4317 | No | `@opentelemetry/exporter-trace-otlp-grpc` |

The `exporter-*-otlp-http` packages use **HTTP/JSON on port 4318**. For HTTP/protobuf, use `exporter-*-otlp-proto`. Set `OTEL_EXPORTER_OTLP_PROTOCOL=grpc` only when the Collector has a gRPC receiver on port 4317. The HTTP exporters automatically append `/v1/traces` to the base URL — do not add this suffix manually.

## Tsuga Endpoint Configuration

```javascript
// gRPC exporter (recommended for Node.js)
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { Metadata } = require('@grpc/grpc-js');

const metadata = new Metadata();
metadata.set('tsuga-ingestion-key', process.env.TSUGA_INGESTION_KEY);

const traceExporter = new OTLPTraceExporter({
  url: 'https://ingest.<region>.tsuga.cloud:443',
  metadata,
});
```

```javascript
// HTTP/protobuf exporter
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-proto');

const traceExporter = new OTLPTraceExporter({
  url: 'https://ingest.<region>.tsuga.cloud:443/v1/traces',
  headers: {
    'tsuga-ingestion-key': process.env.TSUGA_INGESTION_KEY,
  },
});
```

Via environment variables (works with any exporter):

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://ingest.<region>.tsuga.cloud:443
OTEL_EXPORTER_OTLP_HEADERS=tsuga-ingestion-key=<your-key>
OTEL_EXPORTER_OTLP_PROTOCOL=grpc  # or http/protobuf
```

> **gRPC headers note:** When using environment variable `OTEL_EXPORTER_OTLP_HEADERS` with gRPC, the header is passed as gRPC metadata. This is equivalent to using the `Metadata` object in code.

## Common Issues

### No spans arriving at Tsuga

1. Check endpoint: `OTEL_EXPORTER_OTLP_ENDPOINT` must not include `/v1/traces` when using gRPC. For HTTP, either set the full path or let the SDK append it.
2. Verify `otel.js` loads before app code — add `console.log('OTel loaded')` at the top and check process output.
3. Check network: run `curl -v https://ingest.<region>.tsuga.cloud:443` from the same host.
4. Verify the ingestion key is set: `echo $TSUGA_INGESTION_KEY`.

### Spans arrive but have no attributes / wrong service name

- `OTEL_SERVICE_NAME` is not set — defaults to `unknown_service:node`.
> To determine the correct service name, see `references/resource-attributes.md` → **Resolve resource attribute values**.
- `resourceFromAttributes` call happens after `NodeSDK` starts — attributes not merged.

### gRPC connection errors

```
Error: 14 UNAVAILABLE: Connection refused
```

- The collector (or Tsuga) endpoint is not reachable. Check firewalls/security groups.
- Port 4317 may be blocked. Try switching to OTLP/HTTP on port 4318.
- If using `localhost:4317` in Docker, the container cannot reach the host — use `host.docker.internal:4317` or the collector container name.

### Wrong protocol on port 4317

```
Error: socket hang up
```

Using HTTP exporter pointed at port 4317 (gRPC port). Switch to `OTLPTraceExporter` from `exporter-trace-otlp-grpc` or change port to 4318 with HTTP exporter.

### ESM import order issues

In ES Modules, `--import` loads the module before the entry point, but top-level `await` in the init file may not complete before module graph resolution. Use synchronous-compatible init patterns or wrap in an immediately-invoked async function.

## Shutdown / Flush

In-flight spans buffered by `BatchSpanProcessor` are flushed on shutdown. If the process exits before shutdown completes, the last batch of spans is lost.

**NodeSDK (recommended):**

```javascript
process.on('SIGTERM', async () => {
  try {
    await sdk.shutdown();
    console.log('OTel SDK shutdown complete');
  } catch (err) {
    console.error('OTel shutdown error', err);
  }
  process.exit(0);
});
```

**Manual NodeTracerProvider:**

```javascript
process.on('SIGTERM', async () => {
  await tracerProvider.shutdown();  // flushes BatchSpanProcessor
  await meterProvider.shutdown();   // flushes PeriodicExportingMetricReader
  process.exit(0);
});
```

**Common shutdown mistakes:**

- Using `process.on('exit')` — fires synchronously, no async flush possible
- Not calling `sdk.shutdown()` at all — last 5–10 seconds of spans are dropped on SIGTERM
- Calling `process.exit(0)` before awaiting shutdown — cancels the flush

**Force-flush for batch testing:**

If you need to flush immediately (e.g., in a Lambda or short-lived script):

```javascript
const { NodeTracerProvider, SimpleSpanProcessor } = require('@opentelemetry/sdk-trace-node');

// Use SimpleSpanProcessor in short-lived processes — synchronous export per span
const provider = new NodeTracerProvider({
  spanProcessors: [new SimpleSpanProcessor(new OTLPTraceExporter())],
});
```

For Lambda, use `@opentelemetry/sdk-trace-node` with `SimpleSpanProcessor` and call `provider.forceFlush()` before the handler returns.

## Resilience: Collector Unavailable

When the OTLP collector is unreachable, the Node.js OTel SDK does **not** crash the service. The `BatchSpanProcessor` retries exports and drops spans when the retry queue fills. The application continues running.

**Default behavior:** OTLP exporters (gRPC and HTTP) retry on connection failure with exponential backoff (default: 5 retries). Errors go to `DiagLogger`, not thrown to application code.

**Conditional exporter setup:**

```typescript
import { NodeTracerProvider } from '@opentelemetry/sdk-trace-node';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc';

const spanProcessors = [];
const endpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT;
if (endpoint) {
  spanProcessors.push(new BatchSpanProcessor(new OTLPTraceExporter()));
}
// If no endpoint: provider is functional, spans created but not exported

const provider = new NodeTracerProvider({ resource, spanProcessors });
provider.register();
```

**Disable OTel entirely:**
```bash
OTEL_SDK_DISABLED=true node app.js
```

**SDK diagnostic logging** (see export errors without crashing):
```typescript
import { diag, DiagConsoleLogger, DiagLogLevel } from '@opentelemetry/api';
diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.WARN);
// Collector connection errors appear as WARN, not exceptions
```

**Key point:** The JS logs SDK is Development status — validate stability for your use case before relying on it for production log export.
