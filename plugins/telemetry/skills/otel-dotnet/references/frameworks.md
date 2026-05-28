# Framework-Specific Recipes — .NET

## ASP.NET Core

ASP.NET Core is the primary web framework for .NET. OTel instrumentation is first-class via `OpenTelemetry.Instrumentation.AspNetCore`.

```bash
dotnet add package OpenTelemetry --version 1.15.0
dotnet add package OpenTelemetry.Exporter.OpenTelemetryProtocol --version 1.15.0
dotnet add package OpenTelemetry.Extensions.Hosting --version 1.15.0
dotnet add package OpenTelemetry.Instrumentation.AspNetCore --version 1.15.1
dotnet add package OpenTelemetry.Instrumentation.Http --version 1.15.0
```

```csharp
// Program.cs
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;
using System.Diagnostics;

var builder = WebApplication.CreateBuilder(args);

// Declare ActivitySource once — share across the application
// This is typically done in a static class or registered as a singleton
// ActivitySource must be registered with .AddSource() in the builder before use;
// spans created from unregistered sources are silently dropped.

var resourceBuilder = ResourceBuilder.CreateDefault()
    .AddService(serviceName: "aspnetcore-service", serviceVersion: "1.0.0")
    .AddAttributes(new Dictionary<string, object>
    {
        ["deployment.environment.name"] = builder.Environment.EnvironmentName,
    });

builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .SetResourceBuilder(resourceBuilder)
        .AddSource("aspnetcore-service")           // register ActivitySource
        .AddAspNetCoreInstrumentation(opts => {
            opts.Filter = ctx => !ctx.Request.Path.StartsWithSegments("/health");
            opts.RecordException = true;
            opts.EnrichWithHttpRequest = (activity, request) => {
                activity.SetTag("http.client_ip", request.HttpContext.Connection.RemoteIpAddress?.ToString());
            };
        })
        .AddHttpClientInstrumentation(opts => {
            opts.FilterHttpRequestMessage = req =>
                !req.RequestUri?.Host.Contains("health") ?? true;
        })
        .AddOtlpExporter()
    )
    .WithMetrics(metrics => metrics
        .SetResourceBuilder(resourceBuilder)
        .AddMeter("aspnetcore-service")
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddRuntimeInstrumentation()
        .AddOtlpExporter()
    );

builder.Logging.AddOpenTelemetry(logging => {
    logging.SetResourceBuilder(resourceBuilder);
    logging.AddOtlpExporter();
});

var app = builder.Build();
app.MapControllers();
app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
app.Run();
```

**Controller with manual spans:**

The ASP.NET Core instrumentation already creates an HTTP span for every inbound request. Add a manual business span when you need attributes specific to your domain (order IDs, item counts, pricing context) or when the meaningful work happens in a method that isn't on the HTTP path — such as a validation pipeline or a downstream orchestration step.

```csharp
using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;

[ApiController]
[Route("api/[controller]")]
public class OrdersController : ControllerBase
{
    private static readonly ActivitySource _activitySource = new ActivitySource("aspnetcore-service");
    private readonly IOrderService _orderService;

    public OrdersController(IOrderService orderService)
    {
        _orderService = orderService;
    }

    [HttpPost]
    public async Task<IActionResult> CreateOrder([FromBody] CreateOrderRequest request)
    {
        // ASP.NET Core instrumentation creates the HTTP span automatically
        // Add a child span for the business logic
        using var activity = _activitySource.StartActivity("order.validate");
        activity?.SetTag("order.items", request.Items.Count);

        try
        {
            var order = await _orderService.CreateOrderAsync(request);
            activity?.SetTag("order.id", order.Id);
            return CreatedAtAction(nameof(GetOrder), new { id = order.Id }, order);
        }
        catch (ValidationException ex)
        {
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            activity?.RecordException(ex);
            return BadRequest(new { error = ex.Message });
        }
    }
}
```

## gRPC

```bash
dotnet add package OpenTelemetry.Instrumentation.GrpcNetClient --version 1.15.0-beta.1
dotnet add package Grpc.AspNetCore
```

**gRPC Server (in Program.cs):**

```csharp
// gRPC server spans are created automatically by AspNetCore instrumentation
builder.Services.AddGrpc();

// ...

app.MapGrpcService<MyGrpcService>();
```

The gRPC library instruments connection-level and message-level spans automatically via the AspNetCore instrumentation. Add manual spans inside an RPC handler only when you need to attach business context — such as the entity being fetched, validation outcome, or downstream service calls — that the auto-instrumented span doesn't capture.

**gRPC Service with manual spans:**

```csharp
using Grpc.Core;
using System.Diagnostics;

public class MyGrpcService : MyService.MyServiceBase
{
    private static readonly ActivitySource _activitySource = new ActivitySource("my-service");

    public override async Task<GetUserResponse> GetUser(
        GetUserRequest request, ServerCallContext context)
    {
        // gRPC server span created by AspNetCore instrumentation
        // Add child span for DB query
        using var activity = _activitySource.StartActivity("db.get_user");
        activity?.SetTag("user.id", request.UserId);

        var user = await _userRepository.GetAsync(request.UserId);
        if (user == null)
        {
            activity?.SetStatus(ActivityStatusCode.Error, "not found");
            throw new RpcException(new Status(StatusCode.NotFound, "user not found"));
        }

        return new GetUserResponse { Id = user.Id, Name = user.Name };
    }
}
```

**gRPC Client:**

```csharp
// Client spans created automatically by GrpcNetClient instrumentation
builder.Services.AddGrpcClient<MyService.MyServiceClient>(opts => {
    opts.Address = new Uri("http://localhost:50051");
});
```

## Entity Framework Core

```bash
dotnet add package OpenTelemetry.Instrumentation.EntityFrameworkCore --version 1.15.0-beta.1
```

SQL statement capture is enabled by default in recent versions (the `SetDbStatementForText` option was removed). This gives you the full query text in every span, which is invaluable for diagnosing slow or incorrect queries. However, if your queries include user-supplied values -- names, emails, search terms -- those values will appear in your trace backend. Use the `Filter` option to exclude sensitive queries in production environments.

```csharp
.WithTracing(tracing => tracing
    .AddEntityFrameworkCoreInstrumentation(opts => {
        // SetDbStatementForText / SetDbStatementForStoredProcedure were removed in
        // recent versions (SQL capture is now always enabled).
        // Current options: EnrichWithIDbCommand, Filter.
        opts.EnrichWithIDbCommand = (activity, command) => {
            activity.SetTag("db.table", ExtractTableName(command.CommandText));
        };
    })
)
```

EF Core instrumentation creates spans for every query with attributes:
- `db.system` = `mssql` / `postgresql` / etc.
- `db.statement` = SQL text (enabled by default in recent versions)
- `db.name` = database name

## BackgroundService / Worker Service

```csharp
using System.Diagnostics;
using Microsoft.Extensions.Hosting;

public class OrderProcessingWorker : BackgroundService
{
    private static readonly ActivitySource _activitySource = new ActivitySource("my-service");
    private readonly IOrderQueue _queue;

    public OrderProcessingWorker(IOrderQueue queue)
    {
        _queue = queue;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var order in _queue.ReadAllAsync(stoppingToken))
        {
            // Each job is an independent trace — new root span
            using var activity = _activitySource.StartActivity(
                "order.process",
                ActivityKind.Consumer
            );
            activity?.SetTag("order.id", order.Id);

            try
            {
                await ProcessOrderAsync(order, stoppingToken);
                activity?.SetStatus(ActivityStatusCode.Ok);
            }
            catch (Exception ex)
            {
                activity?.RecordException(ex);
                activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            }
        }
    }
}
```

## ActivitySource Registration Reminder

Every `ActivitySource` used in the application must be registered with `.AddSource()`:

```csharp
// All ActivitySource names used anywhere in the codebase must be listed here:
.WithTracing(tracing => tracing
    .AddSource("my-service")             // controllers, services
    .AddSource("my-service.orders")      // order domain
    .AddSource("my-service.payments")    // payment domain
    .AddSource("my-service.workers")     // background workers
)
```

Spans from unregistered sources are **silently dropped** — this is the most common source of missing spans in .NET OTel setups.

## Lifecycle Logging

Structured log events correlated with OTel trace context using `ILogger` + OTel log bridge.

```csharp
// The OTel .NET SDK automatically bridges ILogger to OTel logs when configured:
// builder.Logging.AddOpenTelemetry(logging => logging.AddOtlpExporter());

// ILogger automatically includes trace context when OTel is active
using Microsoft.Extensions.Logging;
using System.Diagnostics;

public class MyService
{
    private readonly ILogger<MyService> _logger;

    public MyService(ILogger<MyService> logger) => _logger = logger;

    // --- Service startup ---
    public void OnStartup()
    {
        _logger.LogInformation("Service starting. Version={Version} Environment={Environment}",
            Environment.GetEnvironmentVariable("APP_VERSION"),
            Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT"));
    }

    // --- Request lifecycle (via ASP.NET Core middleware) ---
    // The OTel ASP.NET Core instrumentation logs request/response automatically.
    // For custom lifecycle logs in a middleware:
    public async Task InvokeAsync(HttpContext ctx, RequestDelegate next)
    {
        _logger.LogInformation("Request received {Method} {Path}",
            ctx.Request.Method, ctx.Request.Path);
        await next(ctx);
        _logger.LogInformation("Request completed {Method} {Path} {Status}",
            ctx.Request.Method, ctx.Request.Path, ctx.Response.StatusCode);
    }

    // --- Graceful shutdown (IHostedService.StopAsync) ---
    public Task StopAsync(CancellationToken ct)
    {
        _logger.LogInformation("Service shutting down");
        return Task.CompletedTask;
        // OTel SDK is shut down by the host automatically via IDisposable
    }
}
```

> When `AddOpenTelemetry()` is configured with `AddOtlpExporter()` for logging, `ILogger` entries are automatically correlated with the active `Activity` (OTel span) — `TraceId` and `SpanId` are included in the OTLP log record without any extra code.

## Integrated Microservice Recipe

Complete example: ASP.NET Core inbound request + HttpClient outbound + custom ActivitySource span + background worker consumer.

```csharp
// Program.cs
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using System.Diagnostics;

var activitySource = new ActivitySource("MyService");

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .SetResourceBuilder(ResourceBuilder.CreateDefault()
            .AddService("my-service"))
        .AddAspNetCoreInstrumentation()      // inbound HTTP
        .AddHttpClientInstrumentation()      // outbound HttpClient
        .AddSource("MyService")              // custom spans
        .AddOtlpExporter());

var app = builder.Build();

app.MapGet("/process", async (HttpClient http) =>
{
    // Custom business span
    using var activity = activitySource.StartActivity("ProcessRequest");
    activity?.SetTag("business.operation", "process");

    // Outbound call — traceparent injected automatically by HttpClientInstrumentation
    var result = await http.GetStringAsync("http://downstream/api");

    activity?.SetTag("downstream.result.length", result.Length);
    return Results.Ok(result);
});

app.Run();
```

**Background worker consumer:**
```csharp
// Worker that processes messages — new root span per message
public class MessageWorker : BackgroundService
{
    private static readonly ActivitySource Source = new("MyService.Worker");

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        await foreach (var message in _queue.ReadAllAsync(ct))
        {
            // Each message is a separate operation — new root span
            using var activity = Source.StartActivity("ProcessMessage",
                ActivityKind.Consumer);
            activity?.SetTag("message.id", message.Id);

            await ProcessAsync(message);
        }
    }
}
```

## Library / SDK Support Matrix

| Library | OTel Support | Notes |
|---|---|---|
| Azure SDK (.NET) | Built-in `ActivitySource` | No extra package needed; add `.AddSource("Azure.*")` |
| MassTransit | Built-in since v8+ — use `.AddSource("MassTransit")` | No separate package needed; auto-instruments publish/consume |
| NServiceBus | Built-in since v8+ — use `endpointConfiguration.EnableOpenTelemetry()` + `.AddSource("NServiceBus.Core")` | No separate package needed for v8+; `NServiceBus.Extensions.Diagnostics.OpenTelemetry` is deprecated (v7 only) |
| Entity Framework Core | `OpenTelemetry.Instrumentation.EntityFrameworkCore` | Traces DB queries |
| Npgsql | Built-in OTel support | Add `.AddNpgsql()` to tracing builder |
| StackExchange.Redis | `OpenTelemetry.Instrumentation.StackExchangeRedis` | |

> **Semconv stability:** Some instrumentation libraries (e.g., `AspNetCore`, `HttpClient`) emit attributes that follow OpenTelemetry semantic conventions. These semconv attributes may not be fully stable — attribute names can change between instrumentation library versions. Pin instrumentation library versions in production and review changelogs before upgrading.
