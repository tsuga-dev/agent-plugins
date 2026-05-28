---
name: otel-dotnet
description: "Use when adding or fixing OTel SDK setup, traces, metrics, logs, or resource attributes in a confirmed .NET codebase — ASP.NET Core, Minimal APIs, Worker Service, Azure Functions, gRPC, or plain C#/F#."
---

# OTel .NET Reference

> **Last verified:** 2026-03-23 | SDK versions: `OpenTelemetry` NuGet 1.15.x / .NET 8+

## When to Use

- The codebase is confirmed .NET (ASP.NET Core, Worker Service, console app, or Azure Functions)
- You need to set up, audit, or fix OTel instrumentation in a C# or F# service
- Covers Minimal APIs, MVC, Blazor backends, gRPC services, and background IHostedService workers
- For language-unknown setups, start with `otel-instrumentation` — it will route here

## Mutation Gate

Before writing any OTel code to the user's source files:
1. Show the proposed change (diff or code block) with a brief explanation
2. Wait for explicit user confirmation ("yes" / "no" / "select specific ones")
3. Apply only after confirmation

After deploy, run `tsuga-smoke-test` to confirm signals arrive.

## Capability Map

| Capability | Reference |
|------------|-----------|
| Setup from scratch (NuGet packages, Program.cs, env vars) | `references/quickstart.md` |
| Auto-instrumentation (NuGet packages + zero-code agent) | `references/auto-instrumentation.md` |
| Instrument traces (spans, kinds, status, Activity API) | `references/spans.md` + `references/propagation.md` |
| Instrument metrics (all instruments, native Meter API) | `references/metrics.md` + `references/otel-reference.md` |
| Instrument logs (ILogger integration, trace correlation) | `references/logs.md` |
| Instrument async messaging (Kafka, RabbitMQ, Service Bus) | `references/async-messaging.md` |
| Audit cross-signal quality | `references/audit-checklist.md` |
| Resolve and audit resource attributes (service.name discovery, env config) | `references/resource-attributes.md` |
| Local testing and verification | `references/local-verification.md` + `references/testing.md` |
| Env vars and instrument types reference | `references/otel-reference.md` |
| Endpoint / protocol troubleshooting | `references/troubleshooting.md` |

## Language-Specific Notes

**Native Activity API:** .NET has `System.Diagnostics.ActivitySource` and `Activity` as its native tracing primitives. The OTel SDK wraps these — it does not replace them. You create `ActivitySource` instances and the SDK picks them up when configured via `.AddSource("name")`. Both the native API and the OTel API co-exist.

**Setup path:** `builder.Services.AddOpenTelemetry()` in `Program.cs` with `.WithTracing()`, `.WithMetrics()`, and `.WithLogging()`. This integrates with the DI container lifecycle and handles shutdown automatically.

**Auto-instrumentation:** `OpenTelemetry.AutoInstrumentation` is a separate zero-code agent (dotnet tool / startup hook), distinct from the NuGet SDK packages. The NuGet instrumentation packages (e.g., `OpenTelemetry.Instrumentation.AspNetCore`) are opt-in and added to the project; the agent runs outside the project entirely.

**Log bridge:** `ILogger` integration is built into the core `OpenTelemetry` package (since SDK 1.9+). With `.WithLogging()` in the DI setup, trace context (`trace_id`, `span_id`) is injected automatically — zero extra code.

**Async context:** `async/await` context flows automatically via `AsyncLocal`. `Activity.Current` is always correct inside an async method that started under an active span.

**Metrics:** Prefer `System.Diagnostics.Metrics.Meter` (native .NET) over the OTel Metrics API directly. The OTel SDK observes native `Meter` instances registered with `.AddMeter("name")`. Both approaches are valid; the native API is more idiomatic.

**Propagation:** `W3CTraceContext` propagator is the default. `AddOtlpExporter()` (zero-arg) reads `OTEL_EXPORTER_OTLP_ENDPOINT` automatically. SDK (manual) default protocol is **gRPC/4317**; auto-instrumentation default is **http/protobuf/4318**. These differ — always set `OTEL_EXPORTER_OTLP_PROTOCOL` explicitly to avoid surprises when mixing SDK and agent paths.

**Kill-switch:** `OTEL_SDK_DISABLED=true` disables the SDK at startup — evaluated by all three providers (traces, metrics, logs). Use as a kill-switch without code changes. New in 1.15.0.

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| `.AddService("name")` without env var fallback | Service name hardcoded; `OTEL_SERVICE_NAME` takes precedence when set | Use `.AddService()` only as a code-level default; always set `OTEL_SERVICE_NAME` per-environment |
| `ActivitySource` name not in `.AddSource()` | Spans silently dropped; `StartActivity()` returns `null` | Add `.AddSource("your-source-name")` to `.WithTracing()` |
| No null-conditional on `activity?.SetTag()` | `NullReferenceException` when span is not sampled | Always use `activity?.SetTag(...)` — `StartActivity()` can return `null` |
| Missing `using` on `Activity` | Span never ends; stays open until GC | Use `using var activity = _source.StartActivity(...)` |
| Hardcoded `opts.Endpoint = new Uri(...)` in `AddOtlpExporter` | Endpoint breaks in non-local environments | Remove lambda; let `OTEL_EXPORTER_OTLP_ENDPOINT` control it |
| `deployment.environment` attribute key (deprecated) | Key missing in Tsuga queries | Use `deployment.environment.name` |
| Consumer span sets parent to producer context | Consumer appears as child of producer HTTP request | Use span Links at creation time (pass `links` to `StartActivity`); see `async-messaging.md` |
| `Meter` name not in `.AddMeter()` | Measurements are no-ops; nothing recorded | Add `.AddMeter("your-meter-name")` to `.WithMetrics()` |

## Related Skills

- `tsuga-smoke-test` — verify signals arrive after deployment
- `tsuga-debug-no-data` — if no telemetry appears in Tsuga after setup
- `tsuga-debug-missing-trace-propagation` — if traces don't link across services
- `otel-semantic-conventions` — attribute naming before writing custom span/metric/log attributes
- `signal-choice-advisor` — metric vs span vs log decision

## Deep Reference

| File | Contents |
|------|----------|
| `references/quickstart.md` | NuGet package setup, SDK init in Program.cs, env vars, post-deploy verification |
| `references/auto-instrumentation.md` | NuGet instrumentation packages, zero-code agent, coverage table |
| `references/spans.md` | Span naming, kind, status, budget table, workflow boundaries, Activity API |
| `references/propagation.md` | HTTP extract/inject, W3CTraceContext default, propagator config, Tsuga validation |
| `references/metrics.md` | All instruments incl. synchronous Gauge, native Meter API, cardinality rules |
| `references/logs.md` | ILogger integration, zero-code trace correlation, verification commands |
| `references/async-messaging.md` | Kafka, RabbitMQ, Service Bus with span Links + semconv |
| `references/resource-attributes.md` | ResourceBuilder.CreateDefault(), env vars, K8s downward API, audit workflow |
| `references/audit-checklist.md` | 11-step live audit, anti-patterns, Tsuga verification commands |
| `references/otel-reference.md` | All instrument types, env vars table, naming rules |
| `references/troubleshooting.md` | Protocol defaults table, no-spans, gRPC errors, resilience |
| `references/local-verification.md` | Console exporter, local collector, SimpleExportProcessor |
| `references/testing.md` | Unit test patterns, in-memory exporters |
