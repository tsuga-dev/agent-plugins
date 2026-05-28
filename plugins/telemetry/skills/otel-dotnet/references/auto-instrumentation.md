# Auto-Instrumentation — .NET

## Overview

.NET OTel provides two auto-instrumentation paths:
1. **NuGet-based instrumentation packages** — opt-in packages added to your project for specific frameworks (ASP.NET Core, HttpClient, EF Core, gRPC, etc.)
2. **OpenTelemetry .NET Automatic Instrumentation** — a zero-code agent similar to Java's javaagent, deployed as a set of native libraries that inject into .NET processes

## NuGet-Based Instrumentation (Recommended)

Install instrumentation packages for your frameworks:

```bash
# ASP.NET Core
dotnet add package OpenTelemetry.Instrumentation.AspNetCore --version 1.15.1

# HttpClient outbound calls
dotnet add package OpenTelemetry.Instrumentation.Http --version 1.15.0

# gRPC client
dotnet add package OpenTelemetry.Instrumentation.GrpcNetClient --version 1.15.0-beta.1

# Entity Framework Core
dotnet add package OpenTelemetry.Instrumentation.EntityFrameworkCore --version 1.15.0-beta.1

# SQL Client (ADO.NET)
dotnet add package OpenTelemetry.Instrumentation.SqlClient --version 1.15.1

# Quartz.NET (job scheduling)
dotnet add package OpenTelemetry.Instrumentation.Quartz --version 1.15.0-beta.1

# StackExchange.Redis
dotnet add package OpenTelemetry.Instrumentation.StackExchangeRedis --version 1.15.0-beta.1

# AWS SDK
dotnet add package OpenTelemetry.Instrumentation.AWS
```

## Setup in Program.cs

```csharp
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;

var builder = WebApplication.CreateBuilder(args);

// ResourceBuilder.CreateDefault() reads OTEL_SERVICE_NAME and OTEL_RESOURCE_ATTRIBUTES
// automatically. OTEL_SERVICE_NAME takes precedence over .AddService() when set.
// Set deployment.environment.name via OTEL_RESOURCE_ATTRIBUTES.
var resourceBuilder = ResourceBuilder.CreateDefault();

builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .SetResourceBuilder(resourceBuilder)
        .AddSource("my-service")                    // REQUIRED — register ActivitySource name
        .AddAspNetCoreInstrumentation(opts => {
            opts.Filter = (context) =>
                !context.Request.Path.StartsWithSegments("/health") &&
                !context.Request.Path.StartsWithSegments("/metrics");
            opts.RecordException = true;
        })
        .AddHttpClientInstrumentation()
        .AddGrpcClientInstrumentation()
        .AddEntityFrameworkCoreInstrumentation()
        .AddSqlClientInstrumentation(opts => {
            // SetDbStatementForText was removed in recent versions (now always enabled).
            // Current options: EnrichWithSqlCommand, Filter, RecordException.
            opts.RecordException = true;
        })
        .AddOtlpExporter()   // zero-arg reads OTEL_EXPORTER_OTLP_ENDPOINT automatically
    )
    .WithMetrics(metrics => metrics
        .SetResourceBuilder(resourceBuilder)
        .AddMeter("my-service")
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddRuntimeInstrumentation()                // GC, thread pool metrics
        .AddProcessInstrumentation()                // CPU, memory metrics
        .AddOtlpExporter()
    );

// Logging
builder.Logging.AddOpenTelemetry(logging => {
    logging.SetResourceBuilder(resourceBuilder);
    logging.AddOtlpExporter();
});
```

## Zero-Code Auto-Instrumentation Agent

For deployment without code changes:

```bash
# Download the agent
curl -L https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/releases/latest/download/otel-dotnet-auto-install.sh | bash

# On Windows (PowerShell):
# Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
# Invoke-Expression "& { $(Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/open-telemetry/opentelemetry-dotnet-instrumentation/main/OpenTelemetryDistribution/PowerShell/install.ps1') }"
```

Run with agent:

```bash
OTEL_SERVICE_NAME=my-service \
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
DOTNET_STARTUP_HOOKS=/root/.otel-dotnet-auto/net/OpenTelemetry.AutoInstrumentation.StartupHook.dll \
dotnet my-app.dll
```

## What Gets Covered Automatically

| Library | Instrumentation package |
|---|---|
| ASP.NET Core (inbound HTTP) | `OpenTelemetry.Instrumentation.AspNetCore` |
| HttpClient (outbound HTTP) | `OpenTelemetry.Instrumentation.Http` |
| gRPC client | `OpenTelemetry.Instrumentation.GrpcNetClient` |
| Entity Framework Core | `OpenTelemetry.Instrumentation.EntityFrameworkCore` |
| ADO.NET / SqlClient | `OpenTelemetry.Instrumentation.SqlClient` |
| Redis (StackExchange) | `OpenTelemetry.Instrumentation.StackExchangeRedis` |
| Quartz.NET | `OpenTelemetry.Instrumentation.Quartz` |
| AWS SDK | `OpenTelemetry.Instrumentation.AWS` |
| .NET runtime metrics (GC, threads) | `OpenTelemetry.Instrumentation.Runtime` |
| Process metrics (CPU, memory) | `OpenTelemetry.Instrumentation.Process` |

## What Needs Manual Instrumentation

Auto-instrumentation does not cover:

- Business logic spans (e.g., `order.validate`, `payment.process`)
- Background `IHostedService` or `BackgroundService` tasks
- Custom message queue consumers not using a supported framework
- In-process domain events

Manual spans use the `ActivitySource` API:

```csharp
using System.Diagnostics;

private static readonly ActivitySource _activitySource = new ActivitySource("my-service");

public async Task ProcessOrderAsync(int orderId)
{
    using var activity = _activitySource.StartActivity("order.process");
    activity?.SetTag("order.id", orderId);

    await ValidateOrderAsync(orderId);
    await FulfillOrderAsync(orderId);
}
```

## ActivitySource Registration

The `ActivitySource` name **must** be registered with `.AddSource()` — otherwise all spans from that source are silently dropped:

```csharp
.WithTracing(tracing => tracing
    .AddSource("my-service")         // REQUIRED
    .AddSource("my-service.orders")  // if you use a separate source for orders
    // ...
)
```

## Verifying Auto-Instrumentation Is Active

```bash
tsuga spans search --query "context.service.name:my-service" --max-results 5
# Look for spans like "GET /api/users/{id}", "SELECT ... FROM users", "HTTP POST"
```
