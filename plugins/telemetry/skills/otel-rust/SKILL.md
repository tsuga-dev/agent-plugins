---
name: otel-rust
description: "Use when adding or fixing OTel SDK setup, traces, metrics, logs, or resource attributes in a confirmed Rust codebase — Axum, Actix-web, tonic (gRPC), rdkafka, or any Tokio-based binary."
---

# OTel Rust Reference

> **Last verified:** 2026-03-23 | SDK versions: `opentelemetry` 0.31.0, `opentelemetry-otlp` 0.31.1, `opentelemetry-sdk` 0.31.0, `tracing-opentelemetry` 0.32.1

## When to Use

- The codebase is confirmed Rust — use this skill directly rather than `otel-instrumentation`.
- Setting up, auditing, or fixing OTel instrumentation in a Rust service using the `tracing` + `tracing-opentelemetry` pattern.
- Adding traces, metrics, or logs via the OTel SDK to an async Tokio service — Axum, Actix-web, tonic (gRPC), rdkafka consumers, or any Tokio-based binary.

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
| Setup from scratch (Cargo.toml, SDK init, shutdown) | `references/quickstart.md` |
| Instrument traces (spans, kinds, status, budget) | `references/spans.md` + `references/propagation.md` |
| Instrument metrics (all instruments incl. synchronous Gauge) | `references/metrics.md` + `references/otel-reference.md` |
| Instrument logs (tracing bridge, log correlation) | `references/logs.md` |
| Instrument async messaging (Kafka, AMQP, SQS) | `references/async-messaging.md` |
| Audit cross-signal quality | `references/audit-checklist.md` |
| Resolve and audit resource attributes (service.name discovery, env config) | `references/resource-attributes.md` |
| Distributed context propagation (HTTP, gRPC) | `references/propagation.md` |
| Endpoint / protocol troubleshooting | `references/troubleshooting.md` |
| Local testing and verification | `references/local-verification.md` |
| All instrument types, env vars, naming rules | `references/otel-reference.md` |

## Language-Specific Notes

**Beta framing — critical:** Rust OTel is Beta for Traces, Metrics, and Logs. All signals are pre-1.0. The API can break between minor versions (e.g., 0.26.x → 0.27.x). Treat any minor version upgrade as potentially breaking — always pin minor versions in `Cargo.toml` and review changelogs carefully before upgrading. The 0.28–0.31 range contained breaking API changes in builder patterns and exporter construction.

**Build — feature flags at compile time:** Protocol selection is a compile-time choice via Cargo features. `opentelemetry-otlp = { features = ["grpc-tonic"] }` for gRPC, `features = ["http-proto"]` for HTTP/protobuf. `OTEL_EXPORTER_OTLP_PROTOCOL` env var is NOT honored at runtime.

**Async runtime requirement:** As of 0.28, `BatchSpanProcessor` and `PeriodicReader` spawn their own background threads and no longer require the `rt-tokio` feature. However, `grpc-tonic` and `reqwest-client` transports still require a running Tokio runtime.

**`tracing` integration — recommended pattern:** `tracing-opentelemetry` 0.32.x bridges Rust's `tracing` crate to OTel. Instrument with `#[tracing::instrument]` or `tracing::info_span!`; spans are exported via OTel automatically. This is the idiomatic Rust path — do not call the raw OTel tracer API directly in application code.

**No auto-instrumentation:** There is no agent or zero-code path for Rust. All instrumentation is manual. The `tracing-opentelemetry` bridge minimizes boilerplate but still requires explicit Cargo setup and SDK init code.

**Log bridge:** `opentelemetry-appender-tracing` bridges `tracing` events → OTel log records. For production, also configure `tracing_subscriber::fmt::layer().json()` so stdout JSON is picked up by the Collector `filelog` receiver.

**Async context propagation:** `tokio::spawn` tasks do not inherit the parent span context automatically. Capture `Context::current()` before `tokio::spawn` and use `.with_context(cx)` (or `.instrument(span)`) inside the task.

**No frameworks.md equivalent yet:** Framework-specific recipes (Axum, Actix-web, tonic) are in `references/propagation.md` inline examples.

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| `grpc-tonic` / `reqwest-client` transport used outside Tokio runtime | Panic at runtime: "no tokio runtime" | Ensure exporter init runs within `#[tokio::main]` or an active Tokio context |
| `SdkTracerProvider` dropped at end of init function | Spans created but never exported | Return the provider from init and keep it alive until shutdown |
| `global::set_tracer_provider` not called | `tracing-opentelemetry` layer is a no-op | Call `global::set_tracer_provider(tracer_provider.clone())` during init |
| `span.enter()` held across `.await` point | Context propagation corrupted; wrong parent spans | Use `#[instrument]` or `.instrument(span)` for async code |
| `OTEL_EXPORTER_OTLP_ENDPOINT` points to port 4318 but `grpc-tonic` feature enabled | Connection refused or silent drops | Match feature to port: `http-proto` → 4318, `grpc-tonic` → 4317 |
| Hardcoding `Resource::builder().with_service_name("...")` | Service name cannot change without recompile | Use `Resource::builder().build()` (includes `EnvResourceDetector` by default); set `OTEL_SERVICE_NAME` externally |
| No shutdown hook | Last batch of spans (up to 5 s) lost on exit | Call `tracer_provider.shutdown()` or `global::shutdown_tracer_provider()` before process exits |
| `deployment.environment` attribute key (deprecated) | Key missing in Tsuga queries | Use `deployment.environment.name` |
| `log::` macros produce no OTel output | Missing log records | Add `tracing-log = "0.2"` + call `LogTracer::init()` at startup |

## Related Skills

- `tsuga-smoke-test` — verify signals arrive after deployment
- `tsuga-debug-no-data` — if no telemetry appears in Tsuga after setup
- `tsuga-debug-missing-trace-propagation` — if traces don't link across services
- `otel-semantic-conventions` — attribute naming before writing custom span/metric/log attributes
- `signal-choice-advisor` — metric vs span vs log decision
- `otel-collector` — Collector config for filelog receiver, OTLP pipelines, tail sampling

## Deep Reference

| File | Contents |
|------|----------|
| `references/quickstart.md` | Cargo.toml setup, feature flags, SDK init (tracer + meter + logger), shutdown hook, env vars |
| `references/spans.md` | Span naming, kind, status, budget table, workflow boundaries, `#[instrument]` pattern |
| `references/propagation.md` | HTTP extract/inject (Axum, reqwest, tonic), propagator config, Tsuga continuity validation |
| `references/metrics.md` | All instruments incl. synchronous Gauge, MeterProvider builder, cardinality rules |
| `references/logs.md` | `opentelemetry-appender-tracing` setup, trace correlation, verification commands |
| `references/async-messaging.md` | Kafka (rdkafka), AMQP (lapin), SQS with span Links + semconv; async context propagation |
| `references/resource-attributes.md` | Required/recommended attributes, env vars, K8s downward API, audit workflow, fix patterns |
| `references/audit-checklist.md` | 11-step live audit, anti-patterns, evidence requirements, output template |
| `references/otel-reference.md` | All instrument types, env vars table, naming rules, span status codes |
| `references/troubleshooting.md` | Protocol defaults, no-spans checklist, gRPC TLS, shutdown/flush, resilience |
| `references/local-verification.md` | Local collector, stdout exporter, SimpleSpanProcessor for dev |
