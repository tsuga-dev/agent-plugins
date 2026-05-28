---
name: otel-python
description: "Use when adding or fixing OTel SDK setup, traces, metrics, logs, log-trace correlation, or resource attributes in a confirmed Python codebase — Flask, Django, FastAPI, Celery, async workers. Also load for Python-specific OTel questions even if the user doesn't say 'instrument'."
---

# OTel Python Reference

> **Last verified:** 2026-03-23 | SDK versions: `opentelemetry-api` 1.40.0, `opentelemetry-sdk` 1.40.0, `opentelemetry-instrumentation` 0.61b0

## When to Use

Use this skill when setting up, auditing, or fixing OpenTelemetry instrumentation in a Python service — Flask, Django, FastAPI, Celery workers, async consumers, or plain Python.

For language-unknown setups, start with `otel-instrumentation`. It routes here once Python is confirmed.

## Mutation Gate

Before writing any OTel setup code to the user's source files:

1. Show the proposed change (diff or code block) with a brief explanation of what it adds
2. Wait for explicit user confirmation ("yes" / "no" / "select specific ones")
3. Apply only after confirmation

After deploy, recommend running `tsuga-smoke-test` to verify signals are arriving.

---

## Capability Map

| Goal | Load these references |
|------|----------------------|
| **Setup from scratch** (manual SDK init) | `references/quickstart.md` |
| **Auto-instrumentation** (zero-code CLI path) | `references/auto-instrumentation.md` |
| **Instrument traces** (spans, kinds, status) | `references/spans.md` + `references/propagation.md` |
| **Instrument metrics** (all instrument types) | `references/metrics.md` + `references/otel-reference.md` |
| **Instrument logs** (correlation, structlog) | `references/logs.md` |
| **Instrument async messaging** (Kafka/SQS/Celery/RabbitMQ) | `references/async-messaging.md` |
| **Framework integration** (Flask, Django, FastAPI) | `references/frameworks.md` |
| **Audit cross-signal quality** | `references/audit-checklist.md` |
| **Resolve and audit resource attributes** (service.name discovery, env config) | `references/resource-attributes.md` |
| **Handle sensitive data** | `assets/sensitive-data.md` |
| **Local testing and verification** | `references/local-verification.md` + `references/testing.md` |
| **Env vars and instrument types** | `references/otel-reference.md` |
| **Endpoint / protocol troubleshooting** | `references/troubleshooting.md` |

---

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| `OTEL_METRICS_EXPORTER` not set | Metrics silently not exported | Set `OTEL_METRICS_EXPORTER=otlp` — spec default is `otlp`, but the Python SDK treats unset as `none` |
| Using gRPC exporter with HTTP-only Collector | Spans never arrive; no error | Switch to `opentelemetry-exporter-otlp-proto-http` or point to port 4317 |
| Hardcoded endpoint in exporter constructor | Breaks in all non-local environments | Remove arg; use `OTEL_EXPORTER_OTLP_ENDPOINT` env var |
| `LoggingInstrumentor` called after logging handlers configured | Log records missing `otelTraceID` | Move `LoggingInstrumentor().instrument()` before `logging.basicConfig()` or any framework logging setup |
| `FlaskInstrumentor().instrument()` called after `Flask()` instantiation | HTTP spans missing | Call `instrument()` before creating the `Flask` app instance (importing Flask first is fine) — or use `instrument_app(app)` on an existing instance |
| No `tracer_provider.shutdown()` on exit | Last spans dropped | Register `atexit.register(tracer_provider.shutdown)` |
| Using `deployment.environment` (old key) | Semconv deprecation warning | Use `deployment.environment.name` (deprecated in semconv v1.27.0) |

---

## Related Skills

- `otel-instrumentation` — entry point for language-unknown setups; routes here
- `otel-semantic-conventions` — check attribute names before inventing custom ones
- `signal-choice-advisor` — metric vs span vs log decision
- `otel-collector` — Collector YAML config, filelog receiver for log ingestion
- `tsuga-smoke-test` — verify signals arrive after deployment
- `tsuga-debug-no-data` — if no telemetry appears in Tsuga after setup
- `tsuga-debug-missing-trace-propagation` — if traces don't link across services

---

## Deep Reference

| Reference | Contents |
|-----------|----------|
| `references/quickstart.md` | pip install, SDK init, env vars, shutdown |
| `references/auto-instrumentation.md` | `opentelemetry-instrument` CLI, bootstrap |
| `references/spans.md` | Span naming, kinds, status, budget, workflow boundaries |
| `references/propagation.md` | HTTP/gRPC context injection/extraction, propagator config |
| `references/metrics.md` | All instrument types, callbacks, cardinality |
| `references/logs.md` | LoggingInstrumentor, structlog, filelog path |
| `references/async-messaging.md` | Kafka, SQS, Celery, RabbitMQ with semconv |
| `references/resource-attributes.md` | Resource.create(), required attrs, audit workflow |
| `references/audit-checklist.md` | Anti-patterns, 11-step cross-signal audit, Tsuga commands |
| `references/frameworks.md` | Flask, Django, FastAPI, SQLAlchemy recipes |
| `references/otel-reference.md` | Instrument API table, env vars, naming rules |
| `references/troubleshooting.md` | Protocol/endpoint issues, shutdown, resilience |
| `references/local-verification.md` | Local Collector setup, smoke test commands |
| `references/testing.md` | In-memory exporters, test patterns |
| `assets/sensitive-data.md` | Attribute scrubbing, PII handling |
