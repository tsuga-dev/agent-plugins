---
name: otel-java
description: "Use when adding or fixing OTel SDK setup or the Java agent, traces, metrics, logs, or resource attributes in a confirmed Java, Kotlin, or Scala codebase — Spring Boot, Quarkus, Micronaut, Vert.x, Kafka, gRPC. Also load for JVM OTel questions."
---

# OTel Java Reference

> **Last verified:** 2026-03-23 | SDK versions: `opentelemetry-bom` 1.60.1, `opentelemetry-javaagent` v2.26.0

## When to Use

Use this skill when setting up, auditing, or fixing OpenTelemetry instrumentation in a Java, Kotlin, or Scala service — whether using the Java agent for auto-instrumentation or initializing the SDK programmatically. Covers Spring Boot, Quarkus, Micronaut, Vert.x, plain Java, Kafka consumers, and gRPC services.

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
| Setup from scratch (programmatic SDK) | `references/quickstart.md` |
| Auto-instrumentation (agent / Spring Boot Starter / Quarkus) | `references/auto-instrumentation.md` |
| Instrument traces (spans, kinds, status) | `references/spans.md` + `references/propagation.md` |
| Instrument metrics (all instruments incl. synchronous Gauge) | `references/metrics.md` + `references/otel-reference.md` |
| Instrument logs (MDC injection, Logback/Log4j2 appenders) | `references/logs.md` |
| Instrument async messaging (Kafka, JMS, SQS, RabbitMQ) | `references/async-messaging.md` |
| Framework integration (Spring, Quarkus, Micronaut) | `references/frameworks.md` |
| Audit cross-signal quality | `references/audit-checklist.md` |
| Resolve and audit resource attributes (service.name discovery, env config) | `references/resource-attributes.md` |
| Handle sensitive data | `assets/sensitive-data.md` |
| Local testing and verification | `references/local-verification.md` + `references/testing.md` |
| Env vars and instrument types reference | `references/otel-reference.md` |
| Endpoint / protocol troubleshooting | `references/troubleshooting.md` |

### Java-Specific Notes

**Three zero-code paths:**
- **Any framework:** Java agent (`-javaagent:opentelemetry-javaagent.jar`) — universal, instruments 100+ libraries
- **Spring Boot:** Spring Boot Starter (`opentelemetry-spring-boot-starter`) — better native-image and startup performance
- **Quarkus:** Quarkus OTel extension (`quarkus-opentelemetry`) — native Quarkus; do NOT use agent with Quarkus

**Scope management:** `span.makeCurrent()` returns a `Scope` that is separate from the span. Both must be closed: `Scope` with try-with-resources; `Span.end()` in `finally`.

**Log bridge:** Trace context injection into logs uses appender JARs (Logback/Log4j2 appender artifacts), not a programmatic call. With the Java agent, MDC injection is automatic with zero code.

**Two version lines:** SDK (`opentelemetry-bom` 1.x) and agent (`opentelemetry-javaagent` 2.x) release independently. All `-alpha` instrumentation artifacts must match the agent version exactly.

**Agent default protocol:** Agent 2.x defaults to `http/protobuf` on port 4318. The autoconfigure module defaults to gRPC/4317. Programmatic `OtlpHttpSpanExporter` defaults to HTTP/4318.

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| `span.end()` not in `finally` | Span left open forever when exception thrown | Move `span.end()` to `finally` block |
| `Scope` not closed via try-with-resources | Context stack corrupted; wrong parent spans | Use `try (Scope scope = span.makeCurrent())` |
| `OtlpGrpcSpanExporter` without autoconfigure module | `OTEL_EXPORTER_OTLP_ENDPOINT` env var ignored | Switch to `OtlpHttpSpanExporter.builder().build()` |
| Hardcoded `.setEndpoint(...)` on exporter | Endpoint breaks in non-local environments | Remove; let `OTEL_EXPORTER_OTLP_ENDPOINT` control it |
| `Resource.builder().put(SERVICE_NAME, ...)` instead of `Resource.getDefault()` | Service name can't change without code deploy | Use `Resource.getDefault()`; set `OTEL_SERVICE_NAME` externally |
| Agent + `buildAndRegisterGlobal()` both called | Agent's `OpenTelemetry` instance overridden | Use `GlobalOpenTelemetry.get()` to retrieve agent's instance |
| `-alpha` artifact version mismatch with agent | `ClassNotFoundException` / runtime errors | Match `-alpha` versions exactly to agent version (e.g., `opentelemetry-logback-mdc-1.0` 2.26.0-alpha with agent v2.26.0). Note: `opentelemetry-instrumentation-annotations` and `opentelemetry-spring-boot-starter` are stable — use `2.26.0` (no `-alpha`). |
| `deployment.environment` attribute key (deprecated) | Key missing in Tsuga queries | Use `deployment.environment.name` |

## Related Skills

- `tsuga-smoke-test` — verify signals arrive after deployment
- `tsuga-debug-no-data` — if no telemetry appears in Tsuga after setup
- `tsuga-debug-missing-trace-propagation` — if traces don't link across services
- `otel-semantic-conventions` — attribute naming before writing custom span/metric/log attributes
- `signal-choice-advisor` — metric vs span vs log decision

## Deep Reference

| File | Contents |
|------|----------|
| `references/quickstart.md` | Maven/Gradle BOM setup, SDK init, shutdown hook, env vars |
| `references/auto-instrumentation.md` | Java agent, Spring Boot Starter, Quarkus, `@WithSpan` |
| `references/spans.md` | Span naming, kind, status, budget table, workflow boundaries |
| `references/propagation.md` | HTTP context extract/inject, B3, Tsuga continuity validation |
| `references/metrics.md` | All instruments incl. synchronous Gauge, cardinality rules |
| `references/logs.md` | MDC auto-injection (agent), Logback/Log4j2 appenders, manual MDC |
| `references/async-messaging.md` | Kafka, JMS/ActiveMQ, SQS, RabbitMQ with span Links + semconv |
| `references/frameworks.md` | Spring MVC, Spring WebFlux, Quarkus, Micronaut recipes |
| `references/resource-attributes.md` | Resource.getDefault(), env vars, K8s downward API, audit workflow |
| `references/audit-checklist.md` | 11-step live audit, anti-patterns, Tsuga verification commands |
| `references/otel-reference.md` | All instrument types, env vars table, naming rules |
| `references/troubleshooting.md` | Protocol defaults table, no-spans, ClassNotFound, resilience |
| `references/local-verification.md` | LoggingSpanExporter, local collector, SimpleSpanProcessor |
| `references/testing.md` | Unit test patterns, InMemorySpanExporter |
| `assets/sensitive-data.md` | Redacting PII from spans, attributes, and logs |
