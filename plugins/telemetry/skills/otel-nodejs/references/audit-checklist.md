# Audit Checklist — Node.js OTel

> **Last verified:** 2026-03-23 | SDK: `@opentelemetry/sdk-node` 0.213.x (experimental) / `@opentelemetry/api` 1.9.x / stable exporters 2.6.x

## Signs OTel Is Already Set Up

Look for these indicators before adding instrumentation:

- `require('@opentelemetry/api')` or `import ... from '@opentelemetry/api'` anywhere in the codebase
- `NodeSDK`, `BasicTracerProvider`, `NodeTracerProvider`, or `MeterProvider` initialization
- `--require ./otel.js` or `--import ./otel.js` in start scripts or `NODE_OPTIONS`
- `@opentelemetry/api` listed in `package.json` `dependencies` or `devDependencies`
- An `otel.js`, `tracing.js`, or `telemetry.js` file in the project root or `src/`

## Dependency Check

Verify versions:

```bash
npm list @opentelemetry/api @opentelemetry/sdk-trace-node @opentelemetry/sdk-metrics @opentelemetry/sdk-node
```

Expected minimum versions:

| Package | Minimum |
|---|---|
| `@opentelemetry/api` | >= 1.9.x |
| `@opentelemetry/sdk-node` | >= 0.213.x |
| `@opentelemetry/sdk-metrics` | >= 0.213.x |
| `@opentelemetry/auto-instrumentations-node` | latest |

Check for version mismatches — all `@opentelemetry/*` packages should use the same major version of `@opentelemetry/api` as a peer.

## Anti-Patterns to Flag

**1. OTel module imported after app modules**

```javascript
// WRONG — app.js loaded before otel.js; HTTP module already patched by Node before instrumentation registers
const app = require('./app');
const { NodeSDK } = require('@opentelemetry/sdk-node');
```

The SDK `--require ./otel.js` must be loaded before any application code.

**2. Not awaiting `sdk.shutdown()`**

```javascript
// WRONG — synchronous exit, in-flight spans may be dropped
process.on('SIGTERM', () => {
  sdk.shutdown();  // returns a Promise — must be awaited
  process.exit(0);
});

// CORRECT
process.on('SIGTERM', async () => {
  await sdk.shutdown();
  process.exit(0);
});
```

**3. Using `process.on('exit')` for shutdown**

The `exit` event fires synchronously — no async operations (including flushing spans) can complete. Use `SIGTERM` or `beforeExit` instead.

**4. Using `startSpan` instead of `startActiveSpan`**

```javascript
// WRONG — span is not set as active; child spans created inside will not have this as parent
const span = tracer.startSpan('op.name');
doWork();  // any spans created here will be orphaned
span.end();

// CORRECT — span is active; child spans link automatically
tracer.startActiveSpan('op.name', (span) => {
  doWork();
  span.end();
});
```

**5. No `NODE_OPTIONS` in process manager / Docker**

If the app is started by PM2, Docker, or a shell script, `NODE_OPTIONS` must be passed to that process. A missing `NODE_OPTIONS` means `otel.js` is never loaded.

**6. Hardcoded `service.name`**

```javascript
// WRONG — service.name cannot be changed at deploy time
const resource = resourceFromAttributes({ 'service.name': 'my-service' });

// CORRECT — driven by environment
const resource = resourceFromAttributes({
  'service.name': process.env.OTEL_SERVICE_NAME || 'my-service',
});
```

**7. `BasicTracerProvider` used instead of `NodeTracerProvider`**

`BasicTracerProvider` (from `@opentelemetry/sdk-trace-base`) lacks Node.js-specific async context propagation. Always use `NodeTracerProvider` from `@opentelemetry/sdk-trace-node` in Node.js services.

**8. Missing `deployment.environment.name`**

Tsuga uses this attribute to filter traces by environment. Set it via:
```bash
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production
```

## Tsuga Verification Commands

After setup or audit, verify signals are arriving:

```bash
# Check for traces
tsuga spans search --query "context.service.name:<your-service>" --max-results 5

# Check for logs with trace correlation
tsuga logs search --query "context.service.name:<your-service> trace_id:*" --max-results 3

# Check for metrics
tsuga metrics list --filter "service.name=<your-service>"
```

If no spans appear within 30 seconds of making requests, check:
1. `OTEL_EXPORTER_OTLP_ENDPOINT` is set correctly
2. The collector or Tsuga ingest endpoint is reachable from the service
3. `otel.js` is actually being loaded (add a `console.log('OTel init')` temporarily)

## 11-Step Live Audit Workflow

Run these steps in order against a running service. Cite evidence for each finding.

**Step 1 — Confirm signals are arriving**

```bash
tsuga spans search --query "context.service.name:<service>" --max-results 5
tsuga logs search --query "context.service.name:<service> trace_id:*" --max-results 3
tsuga metrics list --filter "service.name=<service>"
```

Evidence required: output from each command or explicit "0 results" finding.

**Step 2 — Check resource attributes**

```bash
tsuga spans search --query "context.service.name:<service>" --max-results 1
# Inspect: service.version, deployment.environment.name present?
```

**Step 3 — Check service name source (env var vs hardcoded)**

```bash
kubectl exec -n <ns> <pod> -- env | grep OTEL_SERVICE_NAME
# or: docker inspect <container> | grep OTEL_SERVICE_NAME
```

Expected: `OTEL_SERVICE_NAME=<service>` — not hardcoded in code. `defaultResource()` must be used.

**Step 4 — Check SDK version**

```bash
npm list @opentelemetry/api @opentelemetry/sdk-node
```

Expected: `@opentelemetry/api` >= 1.9.x, `@opentelemetry/sdk-node` >= 0.213.x. If older: update and redeploy.

**Step 5 — Verify tracing.js loads before app code**

```bash
# Check package.json start script or Dockerfile CMD/ENTRYPOINT
grep -r "require.*tracing\|require.*otel\|--require\|NODE_OPTIONS" package.json Dockerfile
```

Expected: `--require ./tracing.js` or `NODE_OPTIONS='--require ./tracing.js'` set before app entry point.

**Step 6 — Check span naming quality**

```bash
tsuga spans search --query "context.service.name:<service>" --max-results 20
# Look for: template-literal paths (/users/abc123), camelCase names (processOrder), missing verb-object
```

**Step 7 — Check span status correctness**

```bash
tsuga spans search --query "context.service.name:<service> status:ERROR" --max-results 10
# Verify: ERROR spans have a message; SERVER 4xx spans are UNSET not ERROR
```

**Step 8 — Check metric naming**

```bash
tsuga metrics list --filter "service.name=<service>"
# Look for: underscore names (http_requests), units in name (_ms, _bytes), service name as prefix
```

If source code path is available, also check instrument type:
- Description containing "current", "active", "open", "in-flight", or "pending" → must use UpDownCounter (not Counter)
- Description containing "duration", "latency", "time", or "size" → must use Histogram (not Counter or Gauge)

**Step 9 — Check log-trace correlation**

```bash
tsuga logs search --query "context.service.name:<service> trace_id:*" --max-results 5
# Verify: trace_id field present on log records; span_id present
```

**Step 10 — Check shutdown handler**

```bash
grep -r "sdk.shutdown\|tracerProvider.shutdown\|SIGTERM" src/ *.js
# Verify: await sdk.shutdown() is called before process.exit(0)
# Verify: NOT using process.on('exit') — this fires synchronously, no async flush
```

**Step 11 — Check exporter configuration**

```bash
kubectl exec -n <ns> <pod> -- env | grep OTEL_EXPORTER
```

Expected:
- `OTEL_EXPORTER_OTLP_ENDPOINT` set (no `url:` hardcoded in exporter constructor)
- Protocol matches the Collector receiver port: HTTP on 4318, gRPC on 4317

## Evidence Requirements

Each audit finding must include:
- **Command used** (CLI command or grep)
- **File path + line number** (for code findings)
- **Observed value** (what was found)
- **Expected value** (what it should be)

## Output Template

```
## Audit: <service-name> — <date>

### Signals Present
- Traces: [yes/no] — tsuga spans search returned N results
- Logs: [yes/no] — tsuga logs search returned N results
- Metrics: [yes/no] — tsuga metrics list returned N entries

### Resource Attributes
- service.name: [value] — source: [env var / hardcoded]
- service.version: [value or MISSING]
- deployment.environment.name: [value or MISSING]

### Findings
1. [Finding] — Evidence: [command + output]
   Fix: [specific action]

### Version Check
- @opentelemetry/api: [version]
- @opentelemetry/sdk-node: [version]
- Shutdown handler: [present / missing]
```

## Instrumentation Quality Rules

**A1 — Every service boundary has a span.** Each inbound HTTP/gRPC handler and each outbound call must produce a span. No gaps at service edges.

**A2 — Span names are low-cardinality.** No user IDs, request IDs, or raw URL paths in span names. Use `{verb} {template}` pattern (e.g., `GET /users/{id}/orders`).

**A3 — Error spans have messages.** Every span with `SpanStatusCode.ERROR` must have a non-empty `message` string in the status object.

**A4 — Resource attributes are externally configurable.** `service.name`, `service.version`, and `deployment.environment.name` must be settable via env vars without a code change.

**A5 — No orphan spans.** Every span except root must have a parent. Scheduled jobs and queue consumers must create a root span, not inherit an unrelated parent.
