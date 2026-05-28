# Audit Checklist — C++ OTel

> **Last verified:** 2026-03-23 | SDK: `opentelemetry-cpp` 1.26.0

## Signs OTel Is Already Set Up

Look for these indicators before adding instrumentation:

- `#include "opentelemetry/trace/provider.h"` in any source file
- `TracerProviderFactory::Create(...)` or `trace_api::Provider::SetTracerProvider(...)` calls
- `opentelemetry-cpp` in `vcpkg.json`, `conanfile.txt`, or `CMakeLists.txt`
- `ShutdownTelemetry()` or `SetTracerProvider({})` call in main/cleanup code
- `OTEL_SERVICE_NAME` or `OTEL_EXPORTER_OTLP_ENDPOINT` in environment config or Dockerfile

## Dependency Check

**vcpkg:**

```bash
vcpkg list | grep opentelemetry
```

**Conan:**

```bash
conan info . | grep opentelemetry
```

**CMake:**

```bash
grep -r "opentelemetry" CMakeLists.txt
```

Expected minimum versions:

| Library | Minimum |
|---------|---------|
| `opentelemetry-cpp` | 1.26.0 |
| gRPC (for OTLP/gRPC exporter) | 1.50.0 |

Check that the correct exporter target (`otlp_http_exporter` or `otlp_grpc_exporter`) is listed in `target_link_libraries` in CMakeLists.txt.

## Anti-Patterns to Flag

**1. Not calling `SetTracerProvider({})` on shutdown**

```cpp
// WRONG — BatchSpanProcessor may not flush; last spans dropped on exit
// Simply letting main() return does not flush the batch processor

// CORRECT
void ShutdownTelemetry() {
    trace_api::Provider::SetTracerProvider({});   // flush + reset
    metrics_api::Provider::SetMeterProvider({});
}
// Call before main() returns or in signal handler flow
```

**2. Raw pointer management instead of `nostd::shared_ptr`**

```cpp
// WRONG — raw pointer may dangle; leads to use-after-free
opentelemetry::trace::Span* span = tracer->StartSpan("op").get();

// CORRECT
auto span = tracer->StartSpan("op");  // nostd::shared_ptr<Span>
```

**3. `span->End()` only in try block, not in catch**

```cpp
// WRONG — exception skips span->End(), leaving span open forever
auto span  = tracer->StartSpan("op");
auto scope = tracer->WithActiveSpan(span);
doWork();
span->End();   // not reached if doWork() throws

// CORRECT — End() in both try and catch paths
auto span  = tracer->StartSpan("op");
auto scope = tracer->WithActiveSpan(span);
try {
    doWork();
    span->End();
} catch (const std::exception& e) {
    span->AddEvent("exception", {{"exception.type", typeid(e).name()},
                                  {"exception.message", e.what()}});
    span->SetStatus(trace_api::StatusCode::kError, e.what());
    span->End();
    throw;
}
```

**4. `SimpleSpanProcessorFactory` in production**

```cpp
// WRONG for production — blocks calling thread on every span export
auto processor = trace_sdk::SimpleSpanProcessorFactory::Create(std::move(exporter));

// CORRECT for production
auto processor = trace_sdk::BatchSpanProcessorFactory::Create(std::move(exporter), {});
```

**5. Missing `deployment.environment.name` in resource attributes**

```cpp
// WRONG — environment missing; queries by environment won't work in Tsuga
auto sdk_resource = resource::Resource::Create({
    {"service.name",    "my-service"},
    {"service.version", "1.0.0"},
});

// CORRECT
auto sdk_resource = resource::Resource::Create({
    {"service.name",               "my-service"},
    {"service.version",            "1.0.0"},
    {"deployment.environment.name", "production"},
});
```

**6. Global propagator not initialized**

```cpp
// WRONG — Extract() and Inject() are no-ops without this call
// traces will not link across services

// CORRECT — call once in InitTelemetry()
opentelemetry::context::propagation::GlobalTextMapPropagator::SetGlobalPropagator(
    opentelemetry::nostd::shared_ptr<opentelemetry::context::propagation::TextMapPropagator>(
        new opentelemetry::trace::propagation::HttpTraceContext()
    )
);
```

**7. gRPC endpoint format**

```cpp
// The SDK default gRPC endpoint is http://localhost:4317.
// The SDK strips the scheme internally when creating the gRPC channel,
// so both formats work:
otlp::OtlpGrpcExporterOptions opts;
opts.endpoint = "http://localhost:4317";   // OK — scheme stripped by SDK
opts.endpoint = "localhost:4317";          // also OK
```

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

Expected: `OTEL_SERVICE_NAME=<service>` — value should be read via `std::getenv()` in init code, not hardcoded as a string literal.

**Step 4 — Check SDK version in CMakeLists.txt or package manifest**

```bash
# vcpkg
grep opentelemetry vcpkg.json

# Conan
grep opentelemetry conanfile.txt

# CMake FetchContent
grep GIT_TAG CMakeLists.txt
```

Expected: `opentelemetry-cpp` 1.26.0. If older: update dependency and rebuild (note: 1.16→1.26 includes config API changes — review CHANGELOG).

**Step 5 — Check exporter target is linked**

```bash
grep -r "otlp_http_exporter\|otlp_grpc_exporter" CMakeLists.txt
```

At least one exporter target must appear in `target_link_libraries`. If absent, spans have nowhere to go.

**Step 6 — Check shutdown is called**

```bash
grep -rn "ShutdownTelemetry\|SetTracerProvider.*{}" src/
```

Expected: `ShutdownTelemetry()` call before `main()` returns, or equivalent `SetTracerProvider({})`. If absent, last spans will be dropped on exit.

**Step 7 — Check span naming quality**

```bash
tsuga spans search --query "context.service.name:<service>" --max-results 20
# Look for: raw paths (/users/123), camelCase (processOrder), missing verb-object pattern
```

**Step 8 — Check span status correctness**

```bash
tsuga spans search --query "context.service.name:<service> status:ERROR" --max-results 10
# Verify: ERROR spans have a description; SERVER 4xx spans are UNSET not ERROR
```

**Step 9 — Check metric naming**

```bash
tsuga metrics list --filter "service.name=<service>"
# Look for: underscore names (http_requests), units in name (_ms, _bytes), service name as prefix
```

If source code path is available, also check instrument type:
- Description containing "current", "active", "open", "in-flight", or "pending" → must use UpDownCounter (not Counter)
- Description containing "duration", "latency", "time", or "size" → must use Histogram (not Counter or Gauge)

**Step 10 — Check log-trace correlation**

```bash
tsuga logs search --query "context.service.name:<service> trace_id:*" --max-results 5
# Verify: trace_id field present on log records; span_id present
```

**Step 11 — Check exporter endpoint configuration**

```bash
kubectl exec -n <ns> <pod> -- env | grep OTEL_EXPORTER
# or check init code for std::getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
```

Expected:
- `OTEL_EXPORTER_OTLP_ENDPOINT` set (no hardcoded URL in C++ source)
- The SDK auto-reads `OTEL_EXPORTER_OTLP_ENDPOINT` in the exporter options constructor
- For gRPC: the default is `http://localhost:4317`; the SDK strips the scheme internally

## Tsuga Verification Commands

```bash
# Check for traces
tsuga spans search --query "context.service.name:<your-service>" --max-results 5

# Check for log-trace correlation
tsuga logs search --query "context.service.name:<your-service> trace_id:*" --max-results 3

# Check for metrics
tsuga metrics list --filter "service.name=<your-service>"
```

If no spans appear:
1. Confirm `ShutdownTelemetry()` is called — without it the `BatchSpanProcessor` may not flush
2. Check `OTEL_EXPORTER_OTLP_ENDPOINT` — default gRPC endpoint is `http://localhost:4317`
3. Verify `SetTracerProvider()` is called before any `GetTracerProvider()` calls
4. Add `SimpleSpanProcessorFactory` temporarily (not for production) to test synchronous export
5. Check that the binary links `opentelemetry-cpp::otlp_grpc_exporter` or `otlp_http_exporter`

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
- service.name: [value] — source: [env var via std::getenv / hardcoded]
- service.version: [value or MISSING]
- deployment.environment.name: [value or MISSING]

### Findings
1. [Finding] — Evidence: [command + output or file:line]
   Fix: [specific action]

### Version Check
- opentelemetry-cpp: [version from vcpkg.json / conanfile.txt / CMakeLists.txt]
- Exporter type: [otlp_http_exporter / otlp_grpc_exporter]
- Shutdown hook present: [yes/no]
```

## Instrumentation Quality Rules

**A1 — Every service boundary has a span.** Each inbound HTTP/gRPC handler and each outbound call must produce a span. No gaps at service edges. C++ has no auto-instrumentation to fill these in automatically.

**A2 — Span names are low-cardinality.** No user IDs, request IDs, or raw URL paths in span names. Use `{verb} {template}` pattern.

**A3 — Error spans have descriptions.** Every span with `StatusCode::kError` must have a non-empty description string passed to `SetStatus()`.

**A4 — Resource attributes are externally configurable.** `service.name`, `service.version`, and `deployment.environment.name` must be settable via environment variables read with `std::getenv()` without a code change.

**A5 — No orphan spans.** Every span except root must have a parent. Background jobs and queue consumers must create a root span (empty `opts.parent`), not inherit an unrelated parent.
