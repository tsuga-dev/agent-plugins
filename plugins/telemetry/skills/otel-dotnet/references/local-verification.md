# Local Verification — .NET

## Overview

Before routing telemetry to a production collector, verify .NET instrumentation by printing spans to stdout using the `OpenTelemetry.Exporter.Console` package. The .NET SDK does **not** read `OTEL_TRACES_EXPORTER` — configure the console exporter in code with `.AddConsoleExporter()`. (The `OTEL_TRACES_EXPORTER` env var is only supported by the zero-code auto-instrumentation agent, not the NuGet SDK.) For short-lived console apps and CLI tools, `TracerProvider` must be disposed before the process exits, or use a `using` block to guarantee cleanup.

## Console Exporter

Install the console exporter package:

```bash
dotnet add package OpenTelemetry.Exporter.Console
```

Configure it with `.AddConsoleExporter()`:

```csharp
using OpenTelemetry;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

using var tracerProvider = Sdk.CreateTracerProviderBuilder()
    .SetResourceBuilder(ResourceBuilder.CreateDefault()
        .AddService("my-service"))
    .AddSource("my-service")
    .AddConsoleExporter()
    .Build();

var activitySource = new System.Diagnostics.ActivitySource("my-service");

using var activity = activitySource.StartActivity("my-operation");
activity?.SetTag("example.key", "value");
DoWork();
```

Each finished `Activity` is printed to stdout with its trace ID, span ID, parent span ID, name, tags, events, and timing.

## SimpleExportProcessor vs BatchExportProcessor

The `.AddConsoleExporter()` call uses `SimpleExportProcessor` by default, which exports synchronously when each span ends. This is the correct behavior for local verification.

| | `SimpleExportProcessor` | `BatchExportProcessor` |
|---|---|---|
| Export timing | Synchronous, on span end | Async, background thread |
| Local testing | Preferred — spans appear immediately | Requires `Dispose()` to flush |
| Production | Not recommended — blocks calling thread | Correct choice |

For production OTLP export, the SDK uses `BatchExportProcessor` automatically. During local development, the console exporter's synchronous default means you see each span as it finishes without waiting for a flush cycle.

## Short-Lived Processes and CLI Tools

`TracerProvider` must be disposed for the exporter to flush any remaining spans. Use a `using` declaration (C# 8+) or an explicit `using` block.

```csharp
// using declaration — Dispose called at end of enclosing scope
using var tracerProvider = Sdk.CreateTracerProviderBuilder()
    .SetResourceBuilder(ResourceBuilder.CreateDefault().AddService("my-job"))
    .AddSource("my-job")
    .AddConsoleExporter()
    .Build();

var activitySource = new System.Diagnostics.ActivitySource("my-job");

using var rootActivity = activitySource.StartActivity("batch.process");
ProcessRecords();
// rootActivity disposed here, then tracerProvider disposed at end of scope
```

For ASP.NET Core hosted services, register `IHostedService` shutdown to trigger disposal:

```csharp
builder.Services.AddOpenTelemetry()
    .WithTracing(b => b
        .AddSource("my-service")
        .AddConsoleExporter());
// IHost.StopAsync() triggers TracerProvider disposal automatically
```

## Inspecting Activities Directly in Tests

In unit tests, `Activity` objects can be inspected without any exporter by subscribing to `ActivitySource` events:

```csharp
using System.Diagnostics;

var recorded = new List<Activity>();
using var listener = new ActivityListener
{
    ShouldListenTo = source => source.Name == "my-service",
    Sample = (ref ActivityCreationOptions<ActivityContext> _) =>
        ActivitySamplingResult.AllDataAndRecorded,
    ActivityStopped = activity => recorded.Add(activity),
};
ActivitySource.AddActivityListener(listener);

// Run code under test
DoWork();

Assert.Equal("expected-operation", recorded[0].DisplayName);
Assert.Equal("expected-value", recorded[0].GetTagItem("example.key"));
```

This approach avoids any exporter dependency and works in test projects without the OTel SDK.

## OTEL_TRACES_EXPORTER=console — Not Supported by the SDK

The .NET OTel SDK does **not** read `OTEL_TRACES_EXPORTER`. Exporter selection is done in code via `.AddConsoleExporter()` or `.AddOtlpExporter()`. The `OTEL_TRACES_EXPORTER` env var is only supported by the **zero-code auto-instrumentation agent** (`OpenTelemetry.AutoInstrumentation`), not by the NuGet-based SDK.

To get console output during local development, configure the exporter in code:

```csharp
.WithTracing(tracing => tracing
    .AddSource("my-service")
    .AddConsoleExporter()   // requires OpenTelemetry.Exporter.Console package
);
```

## Local Collector with Debug Exporter

Run `otelcol-contrib` locally to validate the full OTLP export path. The `debug` exporter prints every received span and metric with full attribute detail.

```yaml
# otelcol-config.yaml — local debug collector
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

exporters:
  debug:
    verbosity: detailed

service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [debug]
    metrics:
      receivers: [otlp]
      exporters: [debug]
```

Point the .NET OTLP exporter at it:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
OTEL_SERVICE_NAME=my-service \
dotnet run
```

Install the OTLP exporter package if not already present:

```bash
dotnet add package OpenTelemetry.Exporter.OpenTelemetryProtocol
```
