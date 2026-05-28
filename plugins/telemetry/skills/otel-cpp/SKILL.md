---
name: otel-cpp
description: "Use when adding or fixing OTel SDK setup, traces, metrics, logs, or resource attributes in a confirmed C++ codebase — gRPC, Crow, cpp-httplib, Boost.Beast, Kafka, or any native C++ binary."
---

# OTel C++ Reference

> **Last verified:** 2026-03-23 | SDK: `opentelemetry-cpp` 1.26.0

## When to Use

- The codebase is confirmed C++ (any standard: C++14, C++17, C++20).
- You need to set up, audit, or fix OpenTelemetry instrumentation in a C++ service — gRPC servers, HTTP APIs (Crow, cpp-httplib, Boost.Beast), Kafka producers/consumers (rdkafka), or any native C++ binary.
- You are routing here from `otel-instrumentation` after language detection.

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
| Build setup (CMake + vcpkg/Conan), SDK init, shutdown | `references/quickstart.md` |
| Instrument traces (spans, kinds, status, budget) | `references/spans.md` + `references/propagation.md` |
| Instrument metrics (all instruments incl. Synchronous Gauge) | `references/metrics.md` + `references/otel-reference.md` |
| Instrument logs (spdlog bridge, trace correlation) | `references/logs.md` |
| Instrument async messaging (Kafka, AMQP, SQS) | `references/async-messaging.md` |
| Resolve and audit resource attributes (service.name discovery, env config) | `references/resource-attributes.md` |
| Audit cross-signal quality | `references/audit-checklist.md` |
| Distributed context propagation (HTTP, gRPC) | `references/propagation.md` |
| Endpoint / protocol troubleshooting | `references/troubleshooting.md` |
| Env vars and instrument types reference | `references/otel-reference.md` |
| Local testing and verification | `references/local-verification.md` |

## Language-Specific Notes

**No auto-instrumentation:** There is no Java agent equivalent. Every span, metric, and log record is created manually via the C++ API. There is no zero-code path. The `references/local-verification.md` file covers local testing only.

**Build system:** CMake is the canonical build system. Dependencies come from vcpkg or Conan — there is no BOM equivalent. `find_package(opentelemetry-cpp CONFIG REQUIRED)` is the standard CMake integration pattern.

**Env-var auto-read:** As of v1.15+, the C++ SDK auto-reads `OTEL_*` exporter vars (e.g., `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_HEADERS`, `OTEL_EXPORTER_OTLP_TIMEOUT`) in the exporter options constructors. Resource attributes (`OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES`) still require `std::getenv()` for use in `Resource::Create()`. The manual pattern in `references/quickstart.md` remains valid for programmatic overrides.

**Exporter choice at link time:** The exporter type (HTTP vs gRPC) is determined by which CMake target you link — `opentelemetry-cpp::otlp_http_exporter` or `opentelemetry-cpp::otlp_grpc_exporter`. There is no runtime protocol switching. Default for new services: `OtlpHttpExporter` on port 4318.

**Context propagation is thread-based:** Use `Context::GetCurrent()` and `tracer->WithActiveSpan(span)` (RAII `Scope` guard) to propagate context across function call stacks. For cross-thread propagation, you must explicitly pass and restore the `Context` object.

**Two-object span lifecycle:** Every active span requires both a `span` object (controls timing) and a `scope` object (controls which span is active in the current thread's context). Destroying `scope` does NOT end the span — `span->End()` must be called explicitly.

**Ecosystem warning:** `opentelemetry-cpp` 1.26.0 is production-ready, but ecosystem tooling is thinner than Java, Go, or Python. There are no framework-specific auto-instrumentation plugins. All HTTP frameworks (cpp-httplib, Crow, Boost.Beast) and messaging clients require manual carrier adapters.

**Log bridge:** The C++ OTel Logs SDK is stable. The preferred bridge pattern is a custom spdlog sink that writes to the OTel `Logger` API. See `references/logs.md`.

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| `span->End()` only in try block, not in catch | Span left open on exception | Call `span->End()` in both try and catch (or use a RAII wrapper) |
| `scope` object destroyed before `span->End()` | Context stack corrupt; wrong parent spans | Keep `scope` alive for the entire span duration |
| No `ShutdownTelemetry()` before process exit | Last spans silently dropped | Call `SetTracerProvider({})` and `SetMeterProvider({})` before `main()` returns |
| gRPC endpoint unreachable | Connection refused | Default is `http://localhost:4317`; SDK strips scheme internally. Check host/port and TLS settings. |
| Hardcoded `{"service.name", "my-service"}` in `Resource::Create()` | Service name requires recompile to change | Read from `std::getenv("OTEL_SERVICE_NAME")` with fallback |
| `SimpleSpanProcessorFactory` in production | Blocks calling thread on every export | Use `BatchSpanProcessorFactory` for production |
| Global propagator not set | `Extract()` and `Inject()` are no-ops; broken traces | Call `GlobalTextMapPropagator::SetGlobalPropagator(...)` in init |
| `deployment.environment` (old key) | Key missing in Tsuga environment queries | Use `deployment.environment.name` |

## Related Skills

- `tsuga-smoke-test` — verify signals arrive after deployment
- `tsuga-debug-no-data` — if no telemetry appears in Tsuga after setup
- `tsuga-debug-missing-trace-propagation` — if traces don't link across services
- `otel-semantic-conventions` — attribute naming before writing custom span/metric/log attributes
- `signal-choice-advisor` — metric vs span vs log decision
- `otel-collector` — Collector YAML, processor ordering, sampling config

## Deep Reference

| File | Contents |
|------|----------|
| `references/quickstart.md` | CMake + vcpkg/Conan setup, SDK init, shutdown hook, env vars, post-deploy verification |
| `references/spans.md` | Span naming, kind, status, budget table, workflow boundaries |
| `references/propagation.md` | HTTP/gRPC extract/inject carriers, propagator config, Tsuga validation |
| `references/metrics.md` | All instruments incl. Synchronous Gauge, cardinality rules, naming rules |
| `references/logs.md` | spdlog bridge to OTel Logs SDK, trace correlation injection, verification |
| `references/async-messaging.md` | Kafka, AMQP, SQS with span Links + semconv, manual inject/extract |
| `references/resource-attributes.md` | Required/recommended attributes, code-defined merge, K8s downward API, audit workflow |
| `references/audit-checklist.md` | 11-step live audit, anti-patterns, evidence requirements, Tsuga verification |
| `references/otel-reference.md` | All instrument types, env vars table, naming rules, span status reference |
| `references/troubleshooting.md` | Protocol defaults table, no-spans, link errors, shutdown, resilience |
| `references/local-verification.md` | SimpleSpanProcessor, local collector, LoggingSpanExporter for local debugging |
