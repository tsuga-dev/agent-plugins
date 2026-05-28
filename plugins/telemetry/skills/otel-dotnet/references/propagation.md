# Distributed Context Propagation — .NET

> **Last verified:** 2026-03-23 | SDK: OpenTelemetry NuGet 1.15.x / .NET 8+

## Overview

Trace context must be explicitly propagated across service boundaries. The W3C TraceContext headers (`traceparent`, `tracestate`) carry the trace ID and span ID between services. In .NET, `Activity` (from `System.Diagnostics`) is the core abstraction — OTel builds on top of it. The ASP.NET Core and HttpClient instrumentation handle HTTP propagation automatically.

> **Async messaging propagation (Kafka, RabbitMQ, Service Bus):**
> See [async-messaging.md](async-messaging.md) for producer/consumer span Link patterns and manual inject/extract code.

## Inbound: Server Context Extraction

**Auto-instrumentation (`AddAspNetCoreInstrumentation`):** Fully automatic. The middleware reads `traceparent` from incoming request headers and creates a child Activity for the request.

**Manual extraction (custom server or background service):**

```csharp
using System.Diagnostics;
using OpenTelemetry;
using OpenTelemetry.Context.Propagation;

private static readonly TextMapPropagator _propagator = Propagators.DefaultTextMapPropagator;
private static readonly ActivitySource _activitySource = new ActivitySource("my-service");

public void HandleRequest(IDictionary<string, string> incomingHeaders)
{
    // Extract parent context from headers
    var parentContext = _propagator.Extract(
        default,
        incomingHeaders,
        (dict, key) => dict.TryGetValue(key, out var value)
            ? new[] { value }
            : Array.Empty<string>()
    );

    Baggage.Current = parentContext.Baggage;

    // Start activity as child of extracted context
    using var activity = _activitySource.StartActivity(
        "handle.request",
        ActivityKind.Server,
        parentContext.ActivityContext
    );
    activity?.SetTag("request.id", "...");
    DoWork();
}
```

**ASP.NET Core middleware (manual):**

```csharp
public class TracingMiddleware
{
    private readonly RequestDelegate _next;
    private static readonly ActivitySource _activitySource = new ActivitySource("my-service");
    private static readonly TextMapPropagator _propagator = Propagators.DefaultTextMapPropagator;

    public TracingMiddleware(RequestDelegate next) => _next = next;

    public async Task InvokeAsync(HttpContext context)
    {
        var parentContext = _propagator.Extract(
            default,
            context.Request.Headers,
            (headers, key) => headers.TryGetValue(key, out var values)
                ? values.ToArray()
                : Array.Empty<string>()
        );

        // GOOD — span naming uses template, not raw path with IDs
        using var activity = _activitySource.StartActivity(
            $"{context.Request.Method} {context.Request.Path}",
            ActivityKind.Server,
            parentContext.ActivityContext
        );

        activity?.SetTag("http.request.method", context.Request.Method);
        activity?.SetTag("http.route", context.Request.Path);

        await _next(context);

        activity?.SetTag("http.response.status_code", context.Response.StatusCode);
    }
}
```

## Outbound: Client Context Injection

**Auto-instrumentation (`AddHttpClientInstrumentation`):** Automatic. The `HttpClient` instrumentation injects `traceparent` into outgoing request headers.

**Manual injection with `HttpClient`:**

```csharp
using System.Diagnostics;
using OpenTelemetry;
using OpenTelemetry.Context.Propagation;

private static readonly TextMapPropagator _propagator = Propagators.DefaultTextMapPropagator;

public async Task<string> CallDownstreamAsync(string url)
{
    var request = new HttpRequestMessage(HttpMethod.Get, url);

    // Inject current activity context into request headers
    _propagator.Inject(
        new PropagationContext(Activity.Current?.Context ?? default, Baggage.Current),
        request,
        (req, key, value) => req.Headers.TryAddWithoutValidation(key, value)
    );

    var response = await _httpClient.SendAsync(request);
    return await response.Content.ReadAsStringAsync();
}
```

**gRPC client injection:**

```csharp
using Grpc.Core;
using OpenTelemetry;
using OpenTelemetry.Context.Propagation;

private static readonly TextMapPropagator _propagator = Propagators.DefaultTextMapPropagator;

public async Task<GetUserResponse> GetUserAsync(int userId)
{
    var headers = new Metadata();

    _propagator.Inject(
        new PropagationContext(Activity.Current?.Context ?? default, Baggage.Current),
        headers,
        (metadata, key, value) => metadata.Add(key, value)
    );

    var callOptions = new CallOptions(headers: headers);
    return await _client.GetUserAsync(new GetUserRequest { UserId = userId }, callOptions);
}
```

## Anti-Pattern: Do Not Merge Separate Workflows

```csharp
// WRONG — makes consumer a child of producer's HTTP request trace
using var activity = _activitySource.StartActivity(
    "job.process",
    ActivityKind.Consumer,
    parentContext.ActivityContext  // sets producer as parent
);

// CORRECT — new root span, linked to producer for cross-trace navigation
// Pass links at creation time (.NET 8+); activity?.AddLink() requires .NET 9+
var links = parentContext.ActivityContext.IsValid()
    ? new[] { new ActivityLink(parentContext.ActivityContext) }
    : Array.Empty<ActivityLink>();

using var activity = _activitySource.StartActivity(
    "job.process",
    ActivityKind.Consumer,
    parentContext: default,
    tags: null,
    links: links
);
```

## Configuring Propagators

The default propagator is W3C TraceContext + W3C Baggage (`tracecontext,baggage`). Use the default for all new services.

Add `b3` only when interoperating with Zipkin-instrumented services, legacy systems, or an Istio/Envoy mesh configured for B3.

```bash
# Add B3 alongside W3C (opt-in only)
OTEL_PROPAGATORS=tracecontext,baggage,b3multi
```

For programmatic configuration:

```csharp
using OpenTelemetry;
using OpenTelemetry.Context.Propagation;
using OpenTelemetry.Extensions.Propagators;

// W3C TraceContext is the default — only configure if you need to add B3
Sdk.SetDefaultTextMapPropagator(new CompositeTextMapPropagator(new TextMapPropagator[]
{
    new TraceContextPropagator(),
    new BaggagePropagator(),
    new B3Propagator()           // add only if needed for B3 interop
}));
```

## Tsuga Trace Continuity Validation

After instrumenting propagation, verify parent/child linkage:

```bash
tsuga spans search --query "context.service.name:<caller-service>" --max-results 5
# Note traceId values from results
tsuga spans search --query "context.service.name:<callee-service> traceId:<trace-id>"
# parentSpanId on callee spans must match spanId from caller spans
```
