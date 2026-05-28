---
name: otel-nodejs
description: "Use when adding or fixing OTel SDK setup, traces, metrics, logs, log-trace correlation, or resource attributes in a confirmed Node.js or TypeScript codebase — Express, Fastify, NestJS, Koa, Kafka, or plain Node."
---

# OTel Node.js Reference

> **Last verified:** 2026-03-23 | SDK versions: `@opentelemetry/sdk-node` 0.213.x (experimental) | `@opentelemetry/api` 1.9.x | stable packages `@opentelemetry/exporter-*` 2.6.x

## When to Use

- The codebase is confirmed Node.js or TypeScript and needs OpenTelemetry instrumentation added, audited, or fixed.
- Signals (spans, metrics, logs) are missing or misconfigured in a Node.js service.
- For language-unknown setups, start with `otel-instrumentation` — it will route here.

## Mutation Gate

Before writing any OTel code to the user's source files:
1. Show the proposed change (diff or code block) with a brief explanation
2. Wait for explicit user confirmation ("yes" / "no" / "select specific ones")
3. Apply only after confirmation

After deploy, run `tsuga-smoke-test` to confirm signals arrive.

## Capability Map

| Capability | Reference |
|------------|-----------|
| Setup from scratch (NodeSDK or manual providers) | `references/quickstart.md` |
| Auto-instrumentation (Express, HTTP, pg, redis, etc.) | `references/auto-instrumentation.md` |
| Instrument traces (spans, kinds, status, budget) | `references/spans.md` + `references/propagation.md` |
| Instrument metrics (all instruments, cardinality rules) | `references/metrics.md` + `references/otel-reference.md` |
| Instrument logs — Winston/pino/bunyan bridge + correlation (**Development status**) | `references/logs.md` |
| Instrument async messaging (Kafka, AMQP, SQS) | `references/async-messaging.md` |
| Framework integration (Express, Fastify, NestJS, Koa) | `references/frameworks.md` |
| Audit cross-signal quality | `references/audit-checklist.md` |
| Resolve and audit resource attributes (service.name discovery, env config) | `references/resource-attributes.md` |
| Local testing and verification | `references/local-verification.md` + `references/testing.md` |
| Env vars and instrument types reference | `references/otel-reference.md` |
| Endpoint / protocol troubleshooting | `references/troubleshooting.md` |

## Language-Specific Notes

**Two SDK init paths:**
- **`NodeSDK` (recommended):** All-in-one init — load via `--require ./tracing.js` or `NODE_OPTIONS`. Handles tracer, meter, logger providers and auto-instrumentations in one call.
- **Manual providers:** `NodeTracerProvider` + `MeterProvider` + `LoggerProvider` separately — use when you need fine-grained processor control, multiple exporters, or are building a library.

**JS SDK 2.x versioning split:** The JS SDK uses two version trains: stable packages (`@opentelemetry/exporter-trace-otlp-http`, `@opentelemetry/api`, etc.) at `≥2.0.0`, and the experimental `NodeSDK` wrapper (`@opentelemetry/sdk-node`) at `≥0.200.0` (currently `0.213.x`). Both are production-ready — the version numbers reflect two separate release trains, not stability levels. Always install matching minor versions within each train.

**Auto-instrumentation:** `@opentelemetry/auto-instrumentations-node` covers Express, HTTP, gRPC, pg, redis, kafkajs, mysql, and more — loaded before app code via `--require ./tracing.js` or `NODE_OPTIONS`. Never import after app modules.

**Log bridge:** No zero-code path like the Java agent. Requires explicit bridge setup: `@opentelemetry/instrumentation-winston`, `pino-opentelemetry-transport`, or `@opentelemetry/instrumentation-bunyan`. Inject `trace_id`, `span_id` into log context. See `references/logs.md`.

**Async model:** Promise/async-await. `AsyncLocalStorageContextManager` handles context propagation automatically. SDK 2.0 requires Node.js `^18.19.0 || >=20.6.0`. Use `startActiveSpan` (not `startSpan`) to set the active context for child spans.

**Shutdown is async:** `sdk.shutdown()` returns a Promise — must `await` it in the signal handler before calling `process.exit(0)`. Failing to await drops the last batch of spans.

**Protocol defaults:** Defaults are SDK-dependent. Set `OTEL_EXPORTER_OTLP_PROTOCOL` and endpoints explicitly in deployment config. The `@opentelemetry/exporter-*-otlp-http` packages use HTTP/JSON on port 4318; the `@opentelemetry/exporter-*-otlp-proto` packages use HTTP/protobuf on port 4318; the `@opentelemetry/exporter-*-otlp-grpc` packages use gRPC on port 4317. Mixed protocol/port causes silent data loss.

**`BasicTracerProvider` warning:** `@opentelemetry/sdk-trace-base` does NOT include Node.js async context propagation. Always use `NodeTracerProvider` from `@opentelemetry/sdk-trace-node`.

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| `require('./tracing.js')` after app imports | Auto-instrumentation patches miss already-loaded modules | Move to `--require ./tracing.js` flag or `NODE_OPTIONS` |
| `sdk.shutdown()` not awaited | Last 5–10 s of spans dropped on SIGTERM | `await sdk.shutdown()` before `process.exit(0)` |
| `startSpan` without `startActiveSpan` | Child spans orphaned — no parent context set | Use `startActiveSpan(name, (span) => { ... })` |
| gRPC exporter pointed at HTTP port 4318 | Spans silently dropped, no error | Use `exporter-trace-otlp-http` for port 4318; `exporter-trace-otlp-grpc` for 4317 |
| Hardcoded endpoint in exporter constructor | Endpoint breaks in non-local environments | Remove; use `OTEL_EXPORTER_OTLP_ENDPOINT` env var |
| `defaultResource()` not used | `service.name` can't change without code deploy | Use `defaultResource()` which reads `OTEL_SERVICE_NAME` |
| `deployment.environment` attribute key (deprecated) | Key missing in Tsuga queries | Use `deployment.environment.name` |
| `BasicTracerProvider` instead of `NodeTracerProvider` | Context lost across async boundaries | Switch to `NodeTracerProvider` from `@opentelemetry/sdk-trace-node` |
| Invalid `k=v` pair in `OTEL_RESOURCE_ATTRIBUTES` | Entire variable silently ignored; all resource attributes absent | Fix or remove the invalid pair — one bad entry silences the whole variable (per-spec, enforced in SDK 2.6.0+) |

## Related Skills

- `tsuga-smoke-test` — verify signals arrive after deployment
- `tsuga-debug-no-data` — if no telemetry appears in Tsuga after setup
- `tsuga-debug-missing-trace-propagation` — if traces don't link across services
- `otel-semantic-conventions` — attribute naming before writing custom span/metric/log attributes
- `signal-choice-advisor` — metric vs span vs log decision
- `otel-collector` — Collector configuration, pipeline setup, filelog receiver for stdout logs

## Deep Reference

| File | Contents |
|------|----------|
| `references/quickstart.md` | npm setup, NodeSDK init, `--require` pattern, shutdown, env vars |
| `references/auto-instrumentation.md` | Auto-instrumentations-node, coverage table, custom instrumentation |
| `references/spans.md` | Span naming, kind, status, budget table, workflow boundaries |
| `references/propagation.md` | HTTP extract/inject, W3C TraceContext default, propagator config, Tsuga validation |
| `references/metrics.md` | All instruments incl. synchronous Gauge, cardinality rules, naming |
| `references/logs.md` | Winston/pino/bunyan bridge, trace_id injection, AsyncLocalStorage context |
| `references/async-messaging.md` | Kafka, AMQP, SQS with span Links + semconv table |
| `references/frameworks.md` | Express, Fastify, NestJS, Koa recipes |
| `references/resource-attributes.md` | defaultResource(), env vars, K8s downward API, audit workflow |
| `references/audit-checklist.md` | 11-step live audit, anti-patterns, Tsuga verification commands |
| `references/otel-reference.md` | All instrument types, env vars table, naming rules |
| `references/troubleshooting.md` | Protocol defaults table, no-spans, gRPC errors, shutdown mistakes |
| `references/local-verification.md` | LoggingSpanExporter, local collector, SimpleSpanProcessor |
| `references/testing.md` | Unit test patterns, InMemorySpanExporter |
