# Audit Checklist — .NET OTel

> **Last verified:** 2026-03-23 | SDK: OpenTelemetry NuGet 1.15.x / .NET 8+

## Signs OTel Is Already Set Up

Look for these indicators before adding instrumentation:

- `using OpenTelemetry` or `using OpenTelemetry.Trace` in any C# file
- `AddOpenTelemetry()` call in `Program.cs` or `Startup.cs`
- `ActivitySource` declaration (`private static readonly ActivitySource _activitySource = ...`)
- `OpenTelemetry` or `OpenTelemetry.Exporter.OpenTelemetryProtocol` in `.csproj`
- `OTEL_SERVICE_NAME` or `OTEL_EXPORTER_OTLP_ENDPOINT` in environment config / `appsettings.json`

## Dependency Check

```bash
dotnet list package | grep OpenTelemetry
```

Expected minimum versions:

| Package | Minimum version |
|---------|-----------------|
| `OpenTelemetry` | 1.15.0 |
| `OpenTelemetry.Api` | 1.15.0 |
| `OpenTelemetry.Exporter.OpenTelemetryProtocol` | 1.15.0 |
| `OpenTelemetry.Extensions.Hosting` | 1.15.0 |
| `OpenTelemetry.Instrumentation.AspNetCore` | 1.15.0 |

Check for version consistency — all `OpenTelemetry.*` packages should be on the same major version. Mixed versions cause silent drops or runtime errors.

## Anti-Patterns to Flag

**1. `ActivitySource` name not registered with `.AddSource()`**

```csharp
// WRONG — "my-service" not in AddSource(); spans silently dropped
private static readonly ActivitySource _source = new ActivitySource("my-service");

// In Program.cs:
.WithTracing(tracing => tracing
    .AddAspNetCoreInstrumentation()
    // Missing: .AddSource("my-service")
)

// CORRECT — register every ActivitySource name used in the application
.WithTracing(tracing => tracing
    .AddSource("my-service")
    .AddAspNetCoreInstrumentation()
)
```

**2. Missing null-conditional on `activity?.SetTag()`**

`_activitySource.StartActivity()` returns `null` when the span is not sampled or the source is not registered:

```csharp
// WRONG — NullReferenceException if activity is null
var activity = _activitySource.StartActivity("op.name");
activity.SetTag("key", "value");  // throws if activity is null

// CORRECT — always use null-conditional operator
using var activity = _activitySource.StartActivity("op.name");
activity?.SetTag("key", "value");
```

**3. Missing `using` on `Activity`**

```csharp
// WRONG — activity not disposed; span remains open until GC
var activity = _activitySource.StartActivity("op.name");
DoWork();
// no Dispose() — span never ends

// CORRECT — using ensures Dispose() is called = span ends
using var activity = _activitySource.StartActivity("op.name");
DoWork();
```

**4. Not disposing `TracerProvider` in non-DI apps**

```csharp
// WRONG — spans may not flush
var tracerProvider = Sdk.CreateTracerProviderBuilder()
    .AddSource("my-service")
    .AddOtlpExporter()
    .Build();
// Process exits — no flush

// CORRECT
using var tracerProvider = Sdk.CreateTracerProviderBuilder()
    .AddSource("my-service")
    .AddOtlpExporter()
    .Build();
// Disposed on using scope exit = flush
```

**5. `Meter` name not registered with `.AddMeter()`**

```csharp
// WRONG — Meter "my-service" not in AddMeter(); measurements are no-ops
private static readonly Meter _meter = new Meter("my-service");

// CORRECT — register every Meter name used
.WithMetrics(metrics => metrics
    .AddMeter("my-service")   // REQUIRED
)
```

**6. Missing `deployment.environment.name`**

```bash
# CORRECT — set via env var
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production
```

```csharp
// Or in code:
var resourceBuilder = ResourceBuilder.CreateDefault()
    .AddAttributes(new Dictionary<string, object>
    {
        ["deployment.environment.name"] = "production"
    });
```

**7. Hardcoded endpoint in `AddOtlpExporter`**

```csharp
// WRONG — cannot change at deploy time
.AddOtlpExporter(opts => opts.Endpoint = new Uri("http://localhost:4317"))

// CORRECT — zero-arg; reads OTEL_EXPORTER_OTLP_ENDPOINT automatically
.AddOtlpExporter()
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

Expected: `OTEL_SERVICE_NAME=<service>` — not hardcoded in code via `.AddService()`.

**Step 4 — Check package versions**

```bash
dotnet list package | grep OpenTelemetry
```

Expected: all `OpenTelemetry.*` packages at 1.15.x or higher, same major version.

**Step 5 — Check ActivitySource registration**

```bash
grep -rn "new ActivitySource" src/
# For each ActivitySource found, verify .AddSource("name") exists in Program.cs
grep -n "AddSource" src/Program.cs
```

Every `ActivitySource` name in code must appear in `.AddSource(...)`.

**Step 6 — Check span naming quality**

```bash
tsuga spans search --query "context.service.name:<service>" --max-results 20
# Look for: raw paths (/users/123), camelCase names (processOrder), missing verb-object pattern
```

**Step 7 — Check span status correctness**

```bash
tsuga spans search --query "context.service.name:<service> status:ERROR" --max-results 10
# Verify: ERROR spans have a description; SERVER 4xx spans are UNSET not ERROR
```

**Step 8 — Check metric naming**

```bash
tsuga metrics list --filter "service.name=<service>"
# Look for: underscore names (http_requests), units in name (_ms, _bytes), service name as prefix
```

If source code path is available, also check instrument type:
- Description containing "current", "active", "open", "in-flight", or "pending" → must use UpDownCounter (not Counter)
- Description containing "duration", "latency", "time", or "size" → must use Histogram (not Counter or Gauge)

**Step 9 — Check log-trace correlation**

```bash
tsuga logs search --query "context.service.name:<service> trace_id:*" --max-results 5
# Verify: trace_id field present on log records; span_id present
```

**Step 10 — Check Activity null-safety (code review)**

```bash
grep -rn "StartActivity" src/
# For each StartActivity call, verify the result uses activity? (null-conditional)
grep -rn "\.SetTag\|\.SetStatus\|\.RecordException" src/
# Verify each call uses ?. not . (without null-conditional)
```

**Step 11 — Check exporter configuration**

```bash
kubectl exec -n <ns> <pod> -- env | grep OTEL_EXPORTER
```

Expected:
- `OTEL_EXPORTER_OTLP_ENDPOINT` set (no `opts.Endpoint` hardcoded in `AddOtlpExporter`)
- `OTEL_EXPORTER_OTLP_PROTOCOL` set if using gRPC (port 4317)

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
- service.name: [value] — source: [env var / hardcoded]
- service.version: [value or MISSING]
- deployment.environment.name: [value or MISSING]

### Findings
1. [Finding] — Evidence: [command + output]
   Fix: [specific action]

### Version Check
- OpenTelemetry NuGet: [version]
- All packages same major version: [yes/no]
```

## Instrumentation Quality Rules

**A1 — Every service boundary has a span.** Each inbound HTTP/gRPC handler and each outbound call must produce a span. No gaps at service edges.

**A2 — Span names are low-cardinality.** No user IDs, request IDs, or raw URL paths in span names. Use `{verb} {template}` pattern.

**A3 — ERROR spans have descriptions.** Every span with `ActivityStatusCode.Error` must have a non-empty description string.

**A4 — Resource attributes are externally configurable.** `service.name`, `service.version`, and `deployment.environment.name` must be settable via env vars without a code change.

**A5 — No orphan spans.** Every span except root must have a parent. Scheduled jobs and queue consumers must create a root span, not inherit an unrelated parent.
