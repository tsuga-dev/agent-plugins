# Logs — .NET OTel

> **Last verified:** 2026-03-23 | SDK: OpenTelemetry NuGet 1.15.x / .NET 8+
>
> Logs SDK is **stable** as of OpenTelemetry NuGet 1.9+.

## Path Selection

| Scenario | Path |
|----------|------|
| ASP.NET Core + ILogger (most common) | **Path A** — zero-code via `AddOpenTelemetry().WithLogging()` |
| Serilog + OTel log pipeline | **Path B** — Serilog with OTel sink |
| NLog + trace correlation | **Path C** — NLog custom LayoutRenderer |
| No DI, minimal setup | **Path D** — manual `Activity.Current` injection |

## Path A — ILogger via AddOpenTelemetry (Recommended, Zero-Code)

With `.WithLogging()` in the DI setup, all `ILogger<T>` records are forwarded to the OTel log pipeline. `trace_id` and `span_id` are injected automatically when a span is active — no code changes to logging call sites.

```csharp
// Program.cs — add WithLogging to the OTel setup
builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .AddSource("my-service")
        .AddAspNetCoreInstrumentation()
        .AddOtlpExporter()
    )
    .WithLogging(logging => logging
        .SetResourceBuilder(ResourceBuilder.CreateDefault())
        .AddOtlpExporter()   // reads OTEL_EXPORTER_OTLP_ENDPOINT automatically
    );

// Usage — ILogger<T> injected via DI as normal; no changes needed
public class OrderService
{
    private readonly ILogger<OrderService> _logger;

    public OrderService(ILogger<OrderService> logger) => _logger = logger;

    public async Task ProcessOrderAsync(int orderId)
    {
        _logger.LogInformation("Processing order {OrderId}", orderId);
        // trace_id and span_id injected automatically when inside an active span
    }
}
```

This approach:
1. Forwards all `ILogger<T>` records to the OTel log pipeline (visible in Tsuga as log telemetry)
2. Auto-injects `trace_id`, `span_id`, and `trace_flags` from the active `Activity`
3. Requires zero changes to existing log call sites

## Path B — Serilog with OTel Sink

```bash
dotnet add package Serilog.Extensions.Hosting
dotnet add package Serilog.Enrichers.Span
```

```csharp
// Program.cs
using Serilog;

Log.Logger = new LoggerConfiguration()
    .Enrich.FromLogContext()
    .Enrich.WithSpan()                       // reads Activity.Current for trace_id/span_id
    .WriteTo.Console(new JsonFormatter())
    .CreateLogger();

builder.Host.UseSerilog();
```

`Enrich.WithSpan()` reads `Activity.Current` and adds `TraceId`, `SpanId`, and `TraceFlags` to every log event while a span is active.

## Path C — NLog Custom LayoutRenderer

```csharp
// Register a custom LayoutRenderer that reads Activity.Current
[LayoutRenderer("trace-id")]
public class TraceIdLayoutRenderer : LayoutRenderer
{
    protected override void Append(StringBuilder builder, LogEventInfo logEvent)
    {
        builder.Append(Activity.Current?.TraceId.ToString() ?? string.Empty);
    }
}

[LayoutRenderer("span-id")]
public class SpanIdLayoutRenderer : LayoutRenderer
{
    protected override void Append(StringBuilder builder, LogEventInfo logEvent)
    {
        builder.Append(Activity.Current?.SpanId.ToString() ?? string.Empty);
    }
}
```

Register in `NLog.config`:

```xml
<nlog>
  <extensions>
    <add assembly="YourAssembly"/>   <!-- REQUIRED — without this, renderers are silently ignored -->
  </extensions>

  <targets>
    <target name="json" xsi:type="File" fileName="app.log">
      <layout xsi:type="JsonLayout">
        <attribute name="trace_id" layout="${trace-id}"/>
        <attribute name="span_id"  layout="${span-id}"/>
        <attribute name="message"  layout="${message}"/>
      </layout>
    </target>
  </targets>
</nlog>
```

## Path D — Manual Activity.Current Injection

Use when you cannot use DI or the OTel log integration but need trace correlation in logs.

```csharp
using System.Diagnostics;

// GOOD — inject trace context manually at the log call site
var activity = Activity.Current;
if (activity?.IsAllDataRequested == true)
{
    using (_logger.BeginScope(new Dictionary<string, object>
    {
        ["trace_id"] = activity.TraceId.ToString(),
        ["span_id"]  = activity.SpanId.ToString()
    }))
    {
        _logger.LogInformation("Processing order {OrderId}", orderId);
    }
}
else
{
    _logger.LogInformation("Processing order {OrderId}", orderId);
}

// BAD — reading Activity.Current outside any active span; fields are always empty
_logger.LogInformation("trace_id={TraceId}", Activity.Current?.TraceId.ToString() ?? "none");
// If called outside a span: logs "trace_id=none" — no correlation
```

## Verification

```bash
# Confirm logs arrive with trace correlation
tsuga logs search --query "context.service.name:<your-service> trace_id:*" --max-results 3

# If trace_id is present but spans are not linking
tsuga spans search --query "context.service.name:<your-service> traceId:<trace-id-from-log>"
```

If verification fails:
- `trace_id` absent from logs → `tsuga-debug-missing-trace-propagation`
- Zero log results → `tsuga-debug-no-data`
