---
name: otel-php
description: "Use when adding or fixing OTel SDK setup, traces, metrics, logs, or resource attributes in a confirmed PHP codebase — Laravel, Symfony, Slim, or plain PHP."
---

# OTel PHP Reference

> **Last verified:** 2026-03-23 | SDK versions: `open-telemetry/sdk` 1.13.0 | `open-telemetry/exporter-otlp` 1.4.0

## When to Use

- Use this skill when setting up, auditing, or fixing OpenTelemetry instrumentation in a PHP service — whether using Laravel, Symfony, or plain PHP.
- For language-unknown setups, start with `otel-instrumentation` — it will route here.
- For Collector configuration (pipelines, processors, exporters), go to `otel-collector`.

## Mutation Gate

Before writing any OTel code to the user's source files:
1. Show the proposed change (diff or code block) with a brief explanation
2. Wait for explicit user confirmation ("yes" / "no" / "select specific ones")
3. Apply only after confirmation

After deploy, run `tsuga-smoke-test` to confirm signals arrive.

## Capability Map

| Capability | Reference |
|------------|-----------|
| Setup from scratch (Composer + SDK init) | `references/quickstart.md` |
| Instrument traces (spans, kinds, status, budget) | `references/spans.md` + `references/propagation.md` |
| Instrument metrics (all instruments incl. synchronous Gauge) | `references/metrics.md` + `references/otel-reference.md` |
| Instrument logs (Monolog handler, trace context injection) | `references/logs.md` |
| Instrument async messaging (Kafka, SQS, span Links) | `references/async-messaging.md` |
| Laravel framework integration | `references/frameworks-laravel.md` |
| Symfony framework integration | `references/frameworks-symfony.md` |
| Other framework integration (Slim, PSR-15, plain PHP) | `references/frameworks-other.md` |
| Auto-instrumentation (ext-opentelemetry + auto-* packages) | `references/auto-instrumentation.md` |
| Audit cross-signal quality | `references/audit-checklist.md` |
| Resolve and audit resource attributes (service.name discovery, env config) | `references/resource-attributes.md` |
| Distributed context propagation | `references/propagation.md` |
| Local testing and verification | `references/local-verification.md` |
| Env vars and instrument types reference | `references/otel-reference.md` |
| Endpoint / protocol troubleshooting | `references/troubleshooting.md` |

## Language-Specific Notes

**Auto-instrumentation requires the C extension:**
PHP auto-instrumentation uses the `ext-opentelemetry` C extension — a compiled PHP extension installed via PECL or a package manager. Composer packages alone are not sufficient. The extension must be installed and enabled in `php.ini` before auto-instrumentation packages (`open-telemetry/opentelemetry-auto-*`) can intercept framework hooks.

**Two auto-instrumentation paths:**
- **Laravel:** `open-telemetry/opentelemetry-auto-laravel` — zero-code when `ext-opentelemetry` is installed; instruments HTTP, queue, cache, DB
- **Symfony:** `open-telemetry/opentelemetry-auto-symfony` — zero-code when `ext-opentelemetry` is installed; instruments HTTP kernel, commands

**Scope management:** `$span->activate()` returns a `ScopeInterface`. Both `$scope->detach()` and `$span->end()` are required in the `finally` block. `detach()` restores the previous context; `end()` records the span. Omitting `detach()` corrupts the context stack for all subsequent code in the request.

**Log bridge:** Use Monolog handler via `open-telemetry/opentelemetry-logger-monolog` or a custom Monolog `ProcessorInterface` to inject `trace_id`, `span_id`, and `trace_flags` into log records. OTLP log export via the Monolog OTel handler is the production path. Also support stdout JSON logs via Monolog for Collector `filelog` ingestion.

**Execution model:** PHP-FPM is synchronous and process-per-request — no threading concerns, but the SDK reinitializes on every request. Long-running processes (Swoole, RoadRunner, Laravel Octane) keep SDK state across requests; use `forceFlush()` after each request cycle and `shutdown()` on SIGTERM.

**Async messaging:** The PHP ecosystem has limited auto-instrumentation coverage for message queues. Kafka requires the `rdkafka` PHP extension plus manual inject/extract. SQS uses `aws/aws-sdk-php` with manual propagation. See `references/async-messaging.md`.

**Signal stability:**
- Traces: Stable
- Metrics: Stable
- Logs: Stable. OTLP log export via the Monolog OTel handler is a valid production path. Mind runtime model caveats: PHP-FPM (shared-nothing, per-request flush needed) vs long-running processes (Swoole, RoadRunner, Laravel Octane).

**gRPC transport:** To export over gRPC, install `open-telemetry/transport-grpc` in addition to the base exporter.

## Common Mistakes

| Mistake | Correct Pattern |
|---------|----------------|
| Missing `$scope->detach()` in `finally` | Always call `$scope->detach()` before `$span->end()` in `finally` |
| `$span->end()` not in `finally` | Move `$span->end()` to `finally` block — not reachable if work throws |
| Installing `open-telemetry/opentelemetry-auto-*` without `ext-opentelemetry` | Install and enable the C extension first; Composer packages alone do nothing |
| `buildAndRegisterGlobal()` called after first `getTracer()` | Call `buildAndRegisterGlobal()` in the earliest bootstrap, before any service container resolution |
| Hardcoding `service.name` in `ResourceInfo::create()` | Use `ResourceInfoFactory::defaultResource()` which reads `OTEL_SERVICE_NAME` automatically |
| `deployment.environment` attribute key (deprecated) | Use `deployment.environment.name` (semconv 1.22+) |
| Appending `/v1/traces` when using env-var-based auto-config | Only append path in programmatic setup; auto-config appends automatically |
| Consumer span using `setParent($extractedProducerContext)` | Use `setNoParent()` + `addLink()` — consumer and producer are separate traces |
| Missing PSR-18 adapter (`php-http/guzzle7-adapter`) | Always install a PSR-18 HTTP client adapter alongside `open-telemetry/exporter-otlp` |
| `setAutoShutdown(false)` with no manual shutdown | Always use `setAutoShutdown(true)` or register a shutdown function |

## Related Skills

- `tsuga-smoke-test` — verify signals arrive after deployment
- `tsuga-debug-no-data` — if no telemetry appears in Tsuga after setup
- `tsuga-debug-missing-trace-propagation` — if traces don't link across services
- `otel-semantic-conventions` — attribute naming before writing custom span/metric/log attributes
- `signal-choice-advisor` — metric vs span vs log decision
- `otel-collector` — Collector pipeline configuration, `filelog` receiver for PHP log collection

## Deep Reference

| File | Contents |
|------|----------|
| `references/quickstart.md` | Composer setup, ext-opentelemetry installation, SDK init, env vars, verification |
| `references/spans.md` | Span naming, kind, status, budget table, workflow boundaries |
| `references/propagation.md` | HTTP extract/inject, propagator config, Tsuga continuity validation |
| `references/metrics.md` | All instruments incl. synchronous Gauge, cardinality rules, naming |
| `references/logs.md` | Monolog handler, trace context injection, PHP-FPM model, verification |
| `references/async-messaging.md` | Kafka, SQS with span Links + semconv; coverage table |
| `references/frameworks-laravel.md` | Laravel auto-instrumentation, queue propagation, Octane |
| `references/frameworks-symfony.md` | Symfony auto-instrumentation, kernel events, console commands |
| `references/frameworks-other.md` | Slim, PSR-15 middleware, plain PHP patterns |
| `references/resource-attributes.md` | Required attributes, env vars, K8s downward API, audit workflow |
| `references/audit-checklist.md` | 11-step live audit, anti-patterns, Tsuga verification commands |
| `references/auto-instrumentation.md` | ext-opentelemetry installation, auto-* packages, coverage list |
| `references/otel-reference.md` | All instrument types, env vars table, naming rules |
| `references/troubleshooting.md` | Protocol defaults, no-spans, HttpClientNotFoundException, resilience |
| `references/local-verification.md` | LoggingSpanExporter, local collector, SimpleSpanProcessor |
