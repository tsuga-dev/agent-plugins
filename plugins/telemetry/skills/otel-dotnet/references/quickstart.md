# Quick Start — .NET OTel

> **Last verified:** 2026-03-23 | SDK: OpenTelemetry NuGet 1.15.x / .NET 8+

> Run `dotnet --version` — set `<TargetFramework>` to match the installed version (e.g. `net8.0` for .NET 8.x). Never target a higher version than what is installed.

## NuGet Package Setup

```bash
# Core SDK
dotnet add package OpenTelemetry --version 1.15.0
dotnet add package OpenTelemetry.Api --version 1.15.0
dotnet add package OpenTelemetry.Exporter.OpenTelemetryProtocol --version 1.15.0
dotnet add package OpenTelemetry.Extensions.Hosting --version 1.15.0

# Instrumentation packages (add for each framework in use)
dotnet add package OpenTelemetry.Instrumentation.AspNetCore --version 1.15.0
dotnet add package OpenTelemetry.Instrumentation.Http --version 1.15.0
```

All `OpenTelemetry.*` packages must be on the same major version. Mixed versions cause silent drops or runtime errors.

## SDK Initialization in Program.cs

```csharp
// Program.cs — ASP.NET Core / Worker Service (recommended path)
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;
using OpenTelemetry.Logs;

var builder = WebApplication.CreateBuilder(args);

// ResourceBuilder.CreateDefault() reads OTEL_SERVICE_NAME and OTEL_RESOURCE_ATTRIBUTES
// automatically. OTEL_SERVICE_NAME takes precedence over .AddService() when set.
// Prefer setting service name via env var; use .AddService() only as a code-level default.
var resourceBuilder = ResourceBuilder.CreateDefault();

builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .SetResourceBuilder(resourceBuilder)
        .AddSource("my-service")              // REQUIRED — register ActivitySource name
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddOtlpExporter()                    // reads OTEL_EXPORTER_OTLP_ENDPOINT automatically
    )
    .WithMetrics(metrics => metrics
        .SetResourceBuilder(resourceBuilder)
        .AddMeter("my-service")               // REQUIRED — register Meter name
        .AddAspNetCoreInstrumentation()
        .AddOtlpExporter()
    )
    .WithLogging(logging => logging
        .SetResourceBuilder(resourceBuilder)
        .AddOtlpExporter()                    // reads OTEL_EXPORTER_OTLP_ENDPOINT automatically
    );

var app = builder.Build();
// DI lifecycle handles shutdown — no extra code needed
```

> **Note:** `.AddSource("my-service")` and `.AddMeter("my-service")` register `ActivitySource`
> and `Meter` names for the SDK to observe. These are NOT service identity — they must match
> the names passed to `new ActivitySource("my-service")` and `new Meter("my-service")` in code.

## OTLP Exporter Configuration

`AddOtlpExporter()` (zero-arg) reads the following env vars automatically:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318   # set to http://localhost:4317 for gRPC
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf           # SDK default is grpc; auto-instrumentation default is http/protobuf — set explicitly
OTEL_EXPORTER_OTLP_HEADERS=tsuga-ingestion-key=<key>
```

Do NOT set `opts.Endpoint = new Uri(...)` in the `AddOtlpExporter` lambda — this hardcodes the endpoint and prevents deploy-time configuration.

```csharp
// BAD — hardcoded endpoint; breaks in non-local environments
.AddOtlpExporter(opts => opts.Endpoint = new Uri("http://localhost:4318"))

// GOOD — zero-arg; reads OTEL_EXPORTER_OTLP_ENDPOINT automatically
.AddOtlpExporter()
```

## Shutdown

With `builder.Services.AddOpenTelemetry()`, the `TracerProvider`, `MeterProvider`, and `LoggerProvider` are registered as singletons and disposed automatically when the ASP.NET Core host shuts down. No shutdown hook code is required.

For **console apps or non-DI setups**:

```csharp
// using ensures Dispose() is called on process exit = spans flushed
using var tracerProvider = Sdk.CreateTracerProviderBuilder()
    .SetResourceBuilder(ResourceBuilder.CreateDefault())
    .AddSource("my-service")
    .AddOtlpExporter()
    .Build();

DoWork();
// Dispose called here by using block — flushes BatchExportActivityProcessor
```

## Required Environment Variables

```bash
# Minimum required — see references/resource-attributes.md to resolve the correct service name
OTEL_SERVICE_NAME=my-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318   # HTTP/protobuf default

# Recommended
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production,service.version=1.4.2

# Always set protocol explicitly — SDK default is gRPC/4317; auto-instrumentation default is http/protobuf/4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf

# gRPC opt-in (Collector gRPC receiver on port 4317)
# OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
# OTEL_EXPORTER_OTLP_PROTOCOL=grpc

# Kill-switch (new in 1.15.0) — disables SDK at startup without code changes
# OTEL_SDK_DISABLED=true
```

## Post-Deploy Verification

```bash
# Confirm traces arrive
tsuga spans search --query "context.service.name:my-service" --max-results 5

# Confirm logs with trace correlation
tsuga logs search --query "context.service.name:my-service trace_id:*" --max-results 3

# Confirm metrics
tsuga metrics list --filter "service.name=my-service"
```

If no data: `tsuga-debug-no-data` skill.
If traces don't link across services: `tsuga-debug-missing-trace-propagation` skill.
