# Local Verification — Node.js

## Overview

Before routing telemetry to a production collector, print spans to stdout to confirm instrumentation is wired correctly. The Node.js OTel SDK provides `ConsoleSpanExporter` out of the box. When using `NodeSDK`, setting `OTEL_TRACES_EXPORTER=console` auto-configures a `ConsoleSpanExporter` with `SimpleSpanProcessor` — no code changes needed. For manual provider setups (without `NodeSDK`), the exporter must be configured in code. For scripts and short-lived processes, `sdk.shutdown()` is required to flush spans before the process exits.

## Console Span Exporter

`ConsoleSpanExporter` is included in `@opentelemetry/sdk-trace-node`. Pair it with `SimpleSpanProcessor` so spans are printed synchronously when each span ends.

```typescript
import { NodeSDK } from "@opentelemetry/sdk-node";
import {
  ConsoleSpanExporter,
  SimpleSpanProcessor,
} from "@opentelemetry/sdk-trace-node";

const sdk = new NodeSDK({
  serviceName: "my-service",
  spanProcessors: [new SimpleSpanProcessor(new ConsoleSpanExporter())],
});

sdk.start();
```

Each finished span is logged to stdout as a JavaScript object containing `traceId`, `spanId`, `parentSpanId`, `name`, `kind`, `attributes`, `status`, and timing fields.

**CommonJS equivalent:**

```javascript
const { NodeSDK } = require("@opentelemetry/sdk-node");
const {
  ConsoleSpanExporter,
  SimpleSpanProcessor,
} = require("@opentelemetry/sdk-trace-node");

const sdk = new NodeSDK({
  serviceName: "my-service",
  spanProcessors: [new SimpleSpanProcessor(new ConsoleSpanExporter())],
});

sdk.start();
```

## SimpleSpanProcessor vs BatchSpanProcessor

| | `SimpleSpanProcessor` | `BatchSpanProcessor` |
|---|---|---|
| Export timing | Synchronous, on span end | Async, background flush |
| Local testing | Preferred — spans appear immediately | May drop spans if process exits before flush |
| Production | Not recommended — adds overhead per span | Correct choice |

Always use `SimpleSpanProcessor` with `ConsoleSpanExporter` during local development. The `NodeSDK` default uses `BatchSpanProcessor` when an OTLP exporter is configured, which can hide spans in short-lived scripts if `shutdown()` is not called.

## Short-Lived Processes and Scripts

Node.js scripts exit when the event loop drains. Spans queued in `BatchSpanProcessor` are dropped unless you explicitly call `sdk.shutdown()`.

```typescript
import { NodeSDK } from "@opentelemetry/sdk-node";
import {
  ConsoleSpanExporter,
  SimpleSpanProcessor,
} from "@opentelemetry/sdk-trace-node";
import { trace } from "@opentelemetry/api";

const sdk = new NodeSDK({
  serviceName: "my-script",
  spanProcessors: [new SimpleSpanProcessor(new ConsoleSpanExporter())],
});

sdk.start();

const tracer = trace.getTracer("my-script");

async function main() {
  const span = tracer.startSpan("etl.run");

  try {
    await processRecords();
  } finally {
    span.end();
    // Flush and shut down before process exits
    await sdk.shutdown();
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
```

For long-running servers, register shutdown on signal:

```typescript
process.on("SIGTERM", () => {
  sdk.shutdown().finally(() => process.exit(0));
});
```

## OTEL_TRACES_EXPORTER=console Environment Variable

`NodeSDK` reads `OTEL_TRACES_EXPORTER` and supports the values `otlp` (default), `zipkin`, `console`, and `none`. When no `traceExporter` or `spanProcessor` is passed in code, the SDK auto-configures the exporter from this env var. Setting `OTEL_TRACES_EXPORTER=console` configures a `ConsoleSpanExporter` with `SimpleSpanProcessor` automatically.

For manual provider setups (without `NodeSDK`), the exporter must still be configured in code. To switch between local console output and OTLP without code changes in a manual setup, use an environment check:

```typescript
import { SpanExporter } from "@opentelemetry/sdk-trace-base";
import {
  ConsoleSpanExporter,
  SimpleSpanProcessor,
  BatchSpanProcessor,
} from "@opentelemetry/sdk-trace-node";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-grpc";

const isLocal = process.env.OTEL_TRACES_EXPORTER === "console";

const exporter: SpanExporter = isLocal
  ? new ConsoleSpanExporter()
  : new OTLPTraceExporter();

const processor = isLocal
  ? new SimpleSpanProcessor(exporter)
  : new BatchSpanProcessor(exporter);
```

## Local Collector with Debug Exporter

Run `otelcol-contrib` locally to validate the full OTLP export path. The `debug` exporter prints every received span and metric with full attribute detail.

```yaml
# otelcol-config.yaml — local debug collector
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

exporters:
  debug:
    verbosity: detailed

service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [debug]
    metrics:
      receivers: [otlp]
      exporters: [debug]
```

Point the Node.js OTLP exporter at it:

```typescript
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-grpc";

const exporter = new OTLPTraceExporter({
  url: "http://localhost:4317",
});
```

```bash
OTEL_SERVICE_NAME=my-service node app.js
```
