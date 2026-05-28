---
name: otel-go
description: "Use when adding or fixing OTel SDK setup, traces, metrics, logs, propagation, or resource attributes in a confirmed Go codebase — net/http, Gin, Echo, Chi, gRPC, Kafka consumers, goroutines. Also load for Go-specific OTel questions."
---

# OTel Go

> **Last verified:** 2026-03-23 | SDK: `go.opentelemetry.io/otel` v1.42.0

## When to Use

Use when the codebase is confirmed Go — HTTP APIs (net/http, Gin, Echo, Chi), gRPC services (tonic/grpc-go), background workers, Kafka consumers, or any Go binary that needs OTel. Covers setup from scratch through full cross-signal audit. For language-unknown setups, start with `otel-instrumentation` — it will route here.

## Mutation Gate

Before writing any OTel setup code or changes to source files:

1. Show the proposed change (diff or code block) with a brief explanation of what it adds
2. Wait for explicit user confirmation ("yes" / "no" / "select specific ones")
3. Apply only after confirmation

After deploy, recommend running `tsuga-smoke-test` — do not block on it.

---

## Capability Map

### Setup from Scratch

New service with no OTel SDK yet.

**Load:** `references/quickstart.md`

Covers: `go get` commands, `resource.Merge(resource.Default(), ...)` init pattern (note: `resource.Default()` includes `telemetry.sdk.*` and `service.name=unknown_service`; for host/process attrs add `resource.WithHost()`/`resource.WithProcess()`), TracerProvider + MeterProvider + LoggerProvider initialization, `OTEL_PROPAGATORS` requirement, env var snippet, post-deploy verification.

---

### Instrument Traces

Add spans to handlers, outbound calls, DB queries, background jobs.

**Load:** `references/spans.md` + `references/propagation.md`

`spans.md` covers: span naming (verb-object, no raw IDs), span kind decision tree, HTTP status → span status mapping, headless operations pattern, span budget table, workflow boundary rules (continue vs new root vs Link).

`propagation.md` covers: multi-service W3C traceparent propagation, async patterns, context threading rules.

---

### Instrument Metrics

Add counters, histograms, gauges, and async instruments.

**Load:** `references/metrics.md` + `references/otel-reference.md`

`metrics.md` covers: all synchronous instruments (Counter, UpDownCounter, Histogram, Gauge — including synchronous Gauge stable since SDK v1.23), all async instruments with `RegisterCallback` batching pattern, cardinality warning, histogram boundary configuration.

`otel-reference.md` covers: full Go instrument API table, naming rules, unit validation, environment variables reference.

---

### Instrument Logs

Set up structured logging with trace-log correlation.

**Load:** `references/logs.md`

Covers: bridge approach (`otelslog.NewHandler` / `otelzap.NewCore` — recommended for automatic `trace_id`/`span_id` injection), manual fallback (custom `traceHandler`), logger choice decision (slog vs zap), log SDK Beta warning, filelog Collector path (JSON stdout → Collector), verification commands.

---

### Instrument Async Messaging

Trace across Kafka, SQS, or RabbitMQ message boundaries.

**Load:** `references/async-messaging.md`

Covers: span Links vs parent-child decision (CONSUMER spans MUST use Links — not parent-child), span naming for messaging, required `messaging.*` semconv attributes, Kafka producer inject + consumer extract patterns (manual; otelsarama contrib is deprecated — Shopify/sarama moved to IBM/sarama), SQS MessageAttributes pattern (otelaws contrib), RabbitMQ AMQP headers pattern, verification.

---

### Framework Integration

Go HTTP frameworks (gin, echo, chi, net/http), gRPC, database drivers.

**Load:** `references/auto-instrumentation.md` + `references/frameworks.md`

Covers: contrib instrumentation packages, middleware wiring, auto-instrumentation options.

---

### Audit Cross-Signal Quality

Full observability review for an existing service: signal presence, correlation, metric naming, span status, cardinality.

**Load:** `references/audit-checklist.md`

Covers: 11-step audit workflow via `tsuga` CLI (signal presence → correlation → metric naming → log structure → trace resource identity → span status → span naming → cardinality → quality report → source code check → validation), evidence requirements, output template, instrumentation quality rules (A1–A5).

---

### Audit Resource Attributes

Check `service.name`, `service.version`, `deployment.environment.name`; detect deprecated `deployment.environment` key; propose SDK init fixes.

**Load:** `references/resource-attributes.md`

Covers: service.name discovery (manifest → run scripts → directory name), where to set OTEL_SERVICE_NAME, required/recommended attribute table, `resource.Merge(resource.Default(), ...)` pattern (vs the less idiomatic `resource.New()`), note that `resource.Default()` only includes `telemetry.sdk.*` and env detector (host/process require explicit `WithHost()`/`WithProcess()`), env var configuration, 3-step audit workflow via `tsuga spans search` + `tsuga logs search`, fix patterns for each issue, mutation gate.

---

### Local Testing and Verification

Run OTel locally, verify signals before deploying.

**Load:** `references/local-verification.md` + `references/testing.md`

---

### Handle Sensitive Data

User asks about PII in spans, safe attributes for logging, credential redaction, or compliance constraints (GDPR, PCI DSS, HIPAA).

**Load:** `assets/sensitive-data.md`

Covers: data types that must never appear in telemetry (credentials, payment data, government IDs, health data), high-risk categories that require evaluation (`user.id`, client IPs, `url.full`, `db.query.text`), URL sanitization patterns, Collector-side redaction as safety net (pointer to `otel-ottl`), compliance context.

---

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| `otlptracegrpc` + port 4318 | Connection refused / protocol error | Use `otlptracehttp` for 4318 (HTTP/protobuf) or `otlptracegrpc` for 4317 (gRPC) |
| Hardcoded `WithEndpoint("http://localhost:4317")` | Endpoint breaks in non-local environments | Remove; use `OTEL_EXPORTER_OTLP_ENDPOINT` env var |
| `otel.SetTextMapPropagator()` never called | Distributed traces don't link across services | Call it in `setupOTel`; default is no-op. Prefer `autoprop.NewTextMapPropagator()` driven by `OTEL_PROPAGATORS` env var — see `references/propagation.md` |
| `resource.New()` without `resource.Default()` | Missing `telemetry.sdk.*` attrs | Use `resource.Merge(resource.Default(), ...)` — add `resource.WithHost()`/`resource.WithProcess()` if host/process attrs are needed |
| Not calling `defer shutdown(ctx)` | Spans not flushed at process exit | Always defer the shutdown function from setup |
| `context.Background()` in HTTP handlers | Root span disconnected from incoming trace | Use `r.Context()` — middleware sets the parent |
| Forgetting `defer span.End()` | Span never closed; memory leak | Always `defer span.End()` immediately after `tracer.Start` |
| Spawning goroutines with `context.Background()` | Trace context lost; orphaned spans | Capture and pass `ctx` into goroutine closures |

> Deeper endpoint/protocol diagnosis → `references/troubleshooting.md`

---

## Related Skills

- `tsuga-smoke-test` — verify signals after deployment
- `tsuga-debug-no-data` — if no telemetry appears after setup
- `tsuga-debug-missing-trace-propagation` — if traces don't link across services
- `otel-collector` — Collector YAML, processor ordering, filelog receiver config
- `otel-semantic-conventions` — attribute naming; check before inventing custom names
- `signal-choice-advisor` — metric vs span vs log decisions
- `tsuga-audit-metrics` / `tsuga-audit-logs` / `tsuga-audit-traces` — deep per-signal audits

---

## Deep Reference

| File | Contents |
|------|----------|
| `references/quickstart.md` | SDK init, deps, env vars, shutdown |
| `references/spans.md` | Span naming, kind, status, budget, workflow boundaries |
| `references/metrics.md` | All instrument types + Go API + cardinality rules |
| `references/logs.md` | slog/zap setup, otelslog/otelzap bridges, trace-log correlation |
| `references/async-messaging.md` | Kafka/SQS/RabbitMQ Go patterns |
| `references/resource-attributes.md` | Resource attr rules + audit workflow |
| `references/audit-checklist.md` | Code anti-patterns + cross-signal audit workflow |
| `references/otel-reference.md` | Full Go instrument API, env vars, naming rules, unit validation |
| `references/propagation.md` | Multi-service context propagation, W3C traceparent |
| `references/auto-instrumentation.md` | Contrib instrumentation packages |
| `references/frameworks.md` | Framework-specific middleware wiring |
| `references/troubleshooting.md` | Endpoint/protocol diagnosis |
| `references/local-verification.md` | Local OTel setup and signal verification |
| `references/testing.md` | Unit testing with OTel |
| `assets/sensitive-data.md` | Sensitive data handling rules |
