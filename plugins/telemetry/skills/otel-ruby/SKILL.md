---
name: otel-ruby
description: "Use when adding or fixing OTel SDK setup, traces, metrics, logs, or resource attributes in a confirmed Ruby codebase — Rails, Sinatra, Rack, Sidekiq, or plain Ruby."
---

# OTel Ruby Reference

> **Last verified:** 2026-03-23 | SDK versions: `opentelemetry-sdk` 1.10.0 | `opentelemetry-exporter-otlp` 0.32.0

## When to Use

- Setting up, auditing, or fixing OpenTelemetry instrumentation in a Ruby or Rails service — Rails, Sinatra, Rack, Sidekiq workers, or plain Ruby
- Adding traces, metrics, or structured log correlation to a confirmed Ruby codebase
- Diagnosing missing telemetry in a Ruby service that already has OTel configured

For language-unknown setups, start with `otel-instrumentation` — it will route here.

## Mutation Gate

Before writing any OTel code to the user's source files:
1. Show the proposed change (diff or code block) with a brief explanation
2. Wait for explicit user confirmation ("yes" / "no" / "select specific ones")
3. Apply only after confirmation

After deploy, run `tsuga-smoke-test` to confirm signals arrive.

## Capability Map

| Capability | Reference |
|------------|-----------|
| Setup from scratch (Gemfile, SDK init, OTLP exporter) | `references/quickstart.md` |
| Instrument traces (spans, kinds, status, budget) | `references/spans.md` |
| Instrument metrics (all instruments, cardinality rules) | `references/metrics.md` |
| Instrument logs (manual trace correlation, structured loggers) | `references/logs.md` |
| Instrument async messaging (Kafka, Sidekiq, span Links) | `references/async-messaging.md` |
| Distributed context propagation (HTTP extract/inject) | `references/propagation.md` |
| Resolve and audit resource attributes (service.name discovery, env config) | `references/resource-attributes.md` |
| Audit cross-signal quality | `references/audit-checklist.md` |
| Endpoint and protocol troubleshooting | `references/troubleshooting.md` |
| Env vars and instrument types reference | `references/otel-reference.md` |
| Auto-instrumentation gems and `use_all` | `references/auto-instrumentation.md` |
| Framework recipes (Rails, Sinatra, Rack) | `references/frameworks.md` |
| Local testing and verification | `references/local-verification.md` |
| Unit test patterns | `references/testing.md` |

## Ruby-Specific Notes

**Setup model:** `OpenTelemetry::SDK.configure` block with `use_all()` for auto-instrumentation. Must be called before any tracer is obtained — calling `tracer_provider.tracer(...)` first locks the SDK as a no-op.

**Auto-instrumentation:** `opentelemetry-instrumentation-*` gems (one per library). `use_all()` loads all installed gems. Manual per-library opt-in: `c.use 'OpenTelemetry::Instrumentation::Rack'`.

**Protocol default:** The `opentelemetry-exporter-otlp` gem uses HTTP/protobuf on port 4318 exclusively. There is no published gRPC exporter gem for Ruby. Always set `OTEL_EXPORTER_OTLP_ENDPOINT` explicitly in deployment config. Do not use port 4317 — the Ruby exporter cannot speak gRPC.

**Log bridge:** No official OTel log bridge gem. Logs are Development status — validate stability for your production use case. For direct OTLP export, use `opentelemetry-logs-sdk` when it meets your stability requirements. The manual path (extract `trace_id`/`span_id` from `OpenTelemetry::Trace.current_span.context`, inject into structured log output via Ougai/Semantic Logger/stdlib, collect via Collector `filelog` receiver) is the stable alternative.

**Async model:** Synchronous by default. Sidekiq for background jobs — context does NOT flow across Sidekiq jobs automatically. Must serialize W3C headers into job arguments and deserialize on the worker side. See `references/async-messaging.md`.

**Shutdown:** Always call `OpenTelemetry.tracer_provider.shutdown` before process exit. The most common Ruby telemetry failure is spans never exported due to missing shutdown. In Puma: add to `on_worker_shutdown`. In Sidekiq: add to `config.on(:shutdown)`.

**Signal maturity:** Traces are Stable. Metrics and Logs are Development status — suitable for instrumentation tasks; validate SDK stability for your production use case before relying on OTLP export for those signals.

## Common Mistakes

| Mistake | Correct Pattern |
|---------|----------------|
| `c.service_name = ENV.fetch('OTEL_SERVICE_NAME', 'my-service')` in configure block | Remove `c.service_name`; Ruby SDK reads `OTEL_SERVICE_NAME` automatically |
| `OTEL_EXPORTER_OTLP_PROTOCOL=grpc` with endpoint on port 4318 | Set endpoint to port 4317 when using gRPC protocol |
| Calling `tracer_provider.tracer(...)` before `configure` | Call `configure` first; getting a tracer locks SDK as no-op |
| Missing `require 'opentelemetry/exporter/otlp'` before configure | Require exporter gem before the configure block; omitting it silently uses no-op exporter |
| Missing `tracer_provider.shutdown` on process exit | Add shutdown to `at_exit`, Puma `on_worker_shutdown`, or Sidekiq `config.on(:shutdown)` |
| `deployment.environment` attribute key (deprecated) | Use `deployment.environment.name` |
| Setting `deployment.environment.name` from `Rails.env` in code | Use `OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production` in env |
| Sidekiq job using `with_parent: extracted_ctx` | Use span Links model — new root span + `add_link`; see `references/async-messaging.md` |

## Related Skills

- `tsuga-smoke-test` — verify signals arrive after deployment
- `tsuga-debug-no-data` — if no telemetry appears in Tsuga after setup
- `tsuga-debug-missing-trace-propagation` — if traces don't link across services
- `otel-semantic-conventions` — attribute naming before writing custom span/metric/log attributes
- `signal-choice-advisor` — metric vs span vs log decision
- `otel-collector` — configure filelog receiver for Ruby log pipeline

## Deep Reference

| File | Contents |
|------|----------|
| `references/quickstart.md` | Gemfile setup, SDK init, OTLP exporter config, shutdown, env vars, post-deploy verification |
| `references/spans.md` | Span naming, kind, status, budget table, workflow boundaries |
| `references/metrics.md` | All instruments including synchronous Gauge, cardinality rules, naming rules |
| `references/logs.md` | Log bridge status, manual trace_id/span_id injection, structured logger patterns |
| `references/async-messaging.md` | Kafka, Sidekiq with span Links model, semconv, manual inject/extract |
| `references/propagation.md` | HTTP context extract/inject, propagator config, Tsuga validation |
| `references/resource-attributes.md` | Required attributes, env var config, K8s downward API, deprecated key note |
| `references/audit-checklist.md` | 11-step live audit, anti-patterns, evidence requirements, output template |
| `references/troubleshooting.md` | Protocol defaults, no-spans checklist, TLS, shutdown issues |
| `references/otel-reference.md` | All instrument types, env vars table, naming rules |
| `references/auto-instrumentation.md` | `use_all()`, per-library opt-in, instrumentation gem list |
| `references/frameworks.md` | Rails, Sinatra, Rack recipes |
| `references/local-verification.md` | LoggingSpanExporter, local collector, SimpleSpanProcessor |
| `references/testing.md` | Unit test patterns, InMemorySpanExporter |
