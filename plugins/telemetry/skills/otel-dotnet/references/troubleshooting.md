# Endpoint, Protocol, and Troubleshooting — .NET

> **Last verified:** 2026-03-23 | SDK: OpenTelemetry NuGet 1.15.x / .NET 8+

## OTLP Protocol Reference

| Protocol | Port | Path auto-appended by SDK? | Package |
|----------|------|---------------------------|---------|
| OTLP/HTTP (`http/protobuf`) | 4318 | Yes (`/v1/traces`, `/v1/metrics`, `/v1/logs`) | `OpenTelemetry.Exporter.OpenTelemetryProtocol` |
| OTLP/gRPC | 4317 | No | `OpenTelemetry.Exporter.OpenTelemetryProtocol` |

**Default protocol is `http/protobuf` on port 4318.** Set `OTEL_EXPORTER_OTLP_PROTOCOL=grpc` to use gRPC.

HTTP exporters auto-append the signal path — do not include `/v1/traces` in `OTEL_EXPORTER_OTLP_ENDPOINT`.

```bash
# HTTP/protobuf (default)
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf   # default; can omit

# gRPC (opt-in)
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```

## Tsuga Endpoint Configuration

**Via environment variables (recommended — no code changes needed):**

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://ingest.<region>.tsuga.cloud:443
OTEL_EXPORTER_OTLP_HEADERS=tsuga-ingestion-key=<your-key>
OTEL_EXPORTER_OTLP_PROTOCOL=grpc  # or http/protobuf
OTEL_SERVICE_NAME=my-service
```

> To determine the correct service name, see `references/resource-attributes.md` → **Resolve resource attribute values**.

**Programmatic (gRPC):**

```csharp
.AddOtlpExporter(opts =>
{
    opts.Endpoint = new Uri("https://ingest.<region>.tsuga.cloud:443");
    opts.Protocol = OtlpExportProtocol.Grpc;
    opts.Headers = $"tsuga-ingestion-key={Environment.GetEnvironmentVariable("TSUGA_INGESTION_KEY")}";
})
```

**Programmatic (HTTP/protobuf):**

```csharp
.AddOtlpExporter(opts =>
{
    opts.Endpoint = new Uri("https://ingest.<region>.tsuga.cloud:443");
    opts.Protocol = OtlpExportProtocol.HttpProtobuf;
    opts.Headers = $"tsuga-ingestion-key={Environment.GetEnvironmentVariable("TSUGA_INGESTION_KEY")}";
    // SDK auto-appends /v1/traces, /v1/metrics, /v1/logs
})
```

## Common Issues

### Spans silently dropped

The most common cause is `ActivitySource` name not registered:

```csharp
// ActivitySource not in AddSource() list → StartActivity() returns null — spans are no-ops
private static readonly ActivitySource _source = new ActivitySource("unregistered-name");
using var activity = _source.StartActivity("op");  // null; silently dropped
```

**Fix:** Add `.AddSource("unregistered-name")` to `.WithTracing()`.

### `NullReferenceException` on `activity.SetTag()`

`StartActivity()` returns `null` when:
- The `ActivitySource` is not registered with `.AddSource()`
- The sampler decided not to sample the span

**Fix:** Always use `activity?.SetTag(...)` with the null-conditional operator.

### gRPC connection fails

```
StatusCode="Unavailable", Detail="Error starting gRPC call."
```

Possible causes:
- Port 4317 not reachable (firewall, security group)
- Protocol mismatch: using `http://` URL with gRPC exporter when HTTPS is required
- Wrong port: sending gRPC to port 4318 (HTTP port) or HTTP to port 4317 (gRPC port)

For Tsuga (TLS required):

```csharp
opts.Endpoint = new Uri("https://ingest.<region>.tsuga.cloud:443");
// No need to configure TLS explicitly — .NET gRPC uses TLS for https:// URIs automatically
```

### Metrics not arriving

1. `Meter` name not registered with `.AddMeter()` — measurements are no-ops
2. Missing `AddRuntimeInstrumentation()` if you expect runtime metrics
3. Exporter configured for traces only — add `.WithMetrics(...)` separately

```csharp
builder.Services.AddOpenTelemetry()
    .WithTracing(...)    // trace config
    .WithMetrics(...);   // metric config — both required
```

### ILogger log correlation missing

When using `ILogger` with OTel's log exporter, trace context is automatically included. If it's missing:

1. Ensure `.WithLogging()` is configured in `AddOpenTelemetry()`

```csharp
builder.Services.AddOpenTelemetry()
    .WithTracing(...)
    .WithLogging(logging => logging
        .SetResourceBuilder(ResourceBuilder.CreateDefault())
        .AddOtlpExporter()
    );
```

2. Serilog users: `Serilog.Enrichers.Span` package with `.Enrich.WithSpan()` reads `Activity.Current`

### `TracerProvider` not flushing in console apps

In non-DI console apps, the `TracerProvider` must be disposed explicitly:

```csharp
using var tracerProvider = Sdk.CreateTracerProviderBuilder()
    .AddSource("my-service")
    .AddOtlpExporter()
    .Build();

DoWork();
// TracerProvider.Dispose() called here — flushes BatchExportActivityProcessor
```

## Shutdown / Flush

The .NET SDK's `BatchExportActivityProcessor` (used internally by `AddOtlpExporter`) buffers spans. Flush happens on `TracerProvider.Dispose()`.

**ASP.NET Core (DI-based):** When using `builder.Services.AddOpenTelemetry()`, the `TracerProvider` is registered as a singleton and disposed automatically when the app shuts down. No extra code needed.

**Console app / Worker Service:**

```csharp
using var tracerProvider = Sdk.CreateTracerProviderBuilder()
    .AddSource("my-service")
    .AddOtlpExporter()
    .Build();

var cts = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) => { e.Cancel = true; cts.Cancel(); };

await RunAsync(cts.Token);
// TracerProvider disposed here by using block — flushes remaining spans
```

**Force flush without disposing:**

```csharp
tracerProvider.ForceFlush(timeoutMilliseconds: 10000);
```

**Common shutdown mistakes:**
- Not `using` or not calling `Dispose()` on `TracerProvider` in console apps — last batch of spans lost
- Calling `Environment.Exit()` — skips `using` block disposal; use `CancellationToken` instead
- `ForceFlush` timeout too short for high-volume services

## Resilience: Collector Unavailable

When the OTLP collector is unreachable, the .NET OTel SDK does **not** throw exceptions to application code. The `BatchExportProcessor` retries exports; spans are dropped when the buffer fills. The service continues normally.

**Disable OTel:**

```bash
OTEL_SDK_DISABLED=true dotnet run
```

**Conditional setup (enable only when endpoint is configured):**

```csharp
var otlpEndpoint = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_ENDPOINT");

builder.Services.AddOpenTelemetry()
    .WithTracing(tracing =>
    {
        tracing.AddSource("my-service");

        if (!string.IsNullOrEmpty(otlpEndpoint))
        {
            tracing.AddOtlpExporter();  // reads OTEL_EXPORTER_OTLP_ENDPOINT automatically
        }
        // If no endpoint: traces created, context propagates, nothing exported
    });
```
