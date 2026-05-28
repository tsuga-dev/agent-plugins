# Span Naming, Kind, and Status Rules — .NET

> **Last verified:** 2026-03-23 | SDK: OpenTelemetry NuGet 1.15.x / .NET 8+
>
> See also: `otel-semantic-conventions` skill for attribute naming; `otel-reference.md` for instrument types.

## Native Activity API and OTel Spans

.NET uses `System.Diagnostics.ActivitySource` and `Activity` as its native tracing primitives. The OTel SDK wraps these — it does not replace them. When you create an `ActivitySource` and register it with `.AddSource("name")`, the SDK picks it up automatically.

```csharp
// Native API — the ActivitySource must be registered with .AddSource() in Program.cs
private static readonly ActivitySource _activitySource = new ActivitySource("my-service");

// OTel API (alternative, less idiomatic in .NET)
// using OpenTelemetry.Trace;
// private static readonly Tracer _tracer = GlobalOpenTelemetry.GetTracerProvider().GetTracer("my-service");

// Prefer the native ActivitySource API for .NET
using var activity = _activitySource.StartActivity("process order", ActivityKind.Internal);
```

Both APIs co-exist in the same process. The native `ActivitySource` approach is idiomatic .NET.

## Span Naming

**Pattern:** `{verb} {object}` in sentence case. Low-cardinality — no IDs, no raw paths.

| BAD | GOOD | Why |
|-----|------|-----|
| `$"GET /users/{userId}/orders"` | `GET /users/{id}/orders` | Interpolated ID creates unbounded cardinality |
| `processOrder` | `process order` | Space-separated verb-object |
| `dbQuery` | `SELECT orders` | Include operation and object |

```csharp
// BAD
using var span = _activitySource.StartActivity($"GET /users/{userId}/orders");

// GOOD
using var span = _activitySource.StartActivity("GET /users/{id}/orders");
span?.SetTag("user.id", userId);
```

## Span Kind Decision Tree

.NET uses `ActivityKind` (maps to OTel SpanKind):

| Scenario | ActivityKind |
|----------|-------------|
| Inbound HTTP/gRPC handler | `ActivityKind.Server` |
| Outbound HTTP, gRPC, DB call | `ActivityKind.Client` |
| Publishing to Kafka/SQS/RabbitMQ | `ActivityKind.Producer` |
| Consuming from queue | `ActivityKind.Consumer` |
| Local method (no I/O) | `ActivityKind.Internal` |

```csharp
// Inbound
using var span = _activitySource.StartActivity("POST /orders", ActivityKind.Server);

// Outbound
using var span = _activitySource.StartActivity("GET products-service", ActivityKind.Client);
```

## HTTP Status → Span Status Mapping

| Span Kind | HTTP 4xx | HTTP 5xx |
|-----------|----------|----------|
| SERVER | **UNSET** (server did its job) | ERROR |
| CLIENT | **ERROR** (call failed) | ERROR |

```csharp
using System.Diagnostics;

// Server span: 400 is NOT an error
if (statusCode >= 500)
{
    span?.SetStatus(ActivityStatusCode.Error, "Internal server error");
}
// 4xx on Server: leave as default Unset

// Client span: 4xx IS an error
if (statusCode >= 400)
{
    span?.SetStatus(ActivityStatusCode.Error, $"HTTP {statusCode}");
}
```

## Headless Operations Pattern

```csharp
// BAD: BackgroundService has no parent context → orphan spans
protected override async Task ExecuteAsync(CancellationToken ct)
{
    using var child = _activitySource.StartActivity("query-stale-records");  // Orphan!
}

// GOOD: create Server root span explicitly
protected override async Task ExecuteAsync(CancellationToken ct)
{
    using var root = _activitySource.StartActivity("nightly-cleanup", ActivityKind.Server);
    root?.SetTag("task.name", "nightly-cleanup");
    root?.SetTag("task.trigger", "cron");

    using var child = _activitySource.StartActivity("query-stale-records");
    // work
}
```

## Span Hygiene Rules

- **< 10 INTERNAL spans per trace** — more indicates over-instrumentation
- **< 20 spans under 5ms** — short spans add noise
- **No orphan spans** — every span except root must have a parent
- **Root spans cannot be CLIENT or PRODUCER**
- **ERROR spans must have a description** — `ActivityStatusCode.Error, "description"`

## Span Budget

| Operation type | Instrument? | Notes |
|----------------|-------------|-------|
| Incoming HTTP request | Always | `AddAspNetCoreInstrumentation()` covers this automatically |
| Outgoing HTTP / gRPC call | Always | `AddHttpClientInstrumentation()` covers this automatically |
| DB query | Always | `AddEntityFrameworkCoreInstrumentation()` / `AddSqlClientInstrumentation()` |
| External service call | Always | — |
| Business transaction (order.place, payment.charge) | Yes | Use manual `ActivitySource` span |
| Internal helper function | Skip | Unless measurably slow or failure-prone |
| Utility called thousands of times per request | Skip | Creates noise; use metric instead |
| Loop iteration (per-item span in a batch) | Only if needed | Confirm sampling is in place first |

Anti-pattern: instrumenting every method. The span budget goal is minimum spans needed to diagnose failures and measure latency at service boundaries.

## Workflow Boundaries

**Rule:** Same user operation across services → continue the trace (propagate W3C `traceparent`). Separate operations, separate queue deliveries, or separate scheduled jobs → new root span.

Never propagate a parent context from one unrelated job into another.

### Continue the trace (outbound HTTP call)

```csharp
using OpenTelemetry;
using OpenTelemetry.Context.Propagation;
using System.Diagnostics;

private static readonly TextMapPropagator _propagator = Propagators.DefaultTextMapPropagator;

// Inject current context into outbound HTTP request
var request = new HttpRequestMessage(HttpMethod.Get, url);
_propagator.Inject(
    new PropagationContext(Activity.Current?.Context ?? default, Baggage.Current),
    request,
    (req, key, value) => req.Headers.TryAddWithoutValidation(key, value)
);
await _httpClient.SendAsync(request);
```

### New root span (scheduled job or batch)

```csharp
// No parent — creates a true root span for the job
using var root = _activitySource.StartActivity("nightly-cleanup", ActivityKind.Server);
root?.SetTag("task.name", "nightly-cleanup");
root?.SetTag("task.trigger", "cron");
// work here — child spans will be children of root
```

### Related but not parent-child (async / queue)

```csharp
// Links connect traces for navigation without making one a child of the other
// Pass links at creation time (.NET 8+); activity?.AddLink() requires .NET 9+
var links = producerContext.ActivityContext.IsValid()
    ? new[] { new ActivityLink(producerContext.ActivityContext) }
    : Array.Empty<ActivityLink>();

using var activity = _activitySource.StartActivity(
    "process order",
    ActivityKind.Consumer,
    parentContext: default,
    tags: null,
    links: links
);
```

> **→** `references/async-messaging.md` — full Kafka, RabbitMQ, and Service Bus patterns with semconv.
