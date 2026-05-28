# Telemetry Testing — .NET

## In-Memory Exporter Setup

```csharp
using OpenTelemetry;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;
using System.Diagnostics;

// Test fixture
public class TelemetryFixture : IDisposable
{
    public List<Activity> FinishedActivities { get; } = new();

    private readonly TracerProvider _tracerProvider;

    public TelemetryFixture()
    {
        _tracerProvider = Sdk.CreateTracerProviderBuilder()
            .AddSource("YourServiceName")
            .AddInMemoryExporter(FinishedActivities)
            .Build();
    }

    public void Dispose() => _tracerProvider?.Dispose();
}
```

## Span Assertions

```csharp
using Xunit;
using System.Diagnostics;

public class OrderServiceTests : IClassFixture<TelemetryFixture>
{
    private readonly TelemetryFixture _telemetry;
    private readonly OrderService _service;

    public OrderServiceTests(TelemetryFixture telemetry)
    {
        _telemetry = telemetry;
        _service = new OrderService();
    }

    [Fact]
    public async Task CreatesServerRootSpan()
    {
        await _service.CreateOrderAsync(new Order { Item = "widget" });

        var spans = _telemetry.FinishedActivities;
        Assert.NotEmpty(spans);

        var rootSpans = spans.Where(s => s.Parent == null).ToList();
        Assert.Single(rootSpans);
        Assert.Equal("POST /orders", rootSpans[0].DisplayName);
        Assert.Equal(ActivityKind.Server, rootSpans[0].Kind);
    }

    [Fact]
    public async Task NoOrphanClientSpans()
    {
        await _service.CreateOrderAsync(new Order { Item = "widget" });

        var orphanClientSpans = _telemetry.FinishedActivities
            .Where(s => (s.Kind == ActivityKind.Client || s.Kind == ActivityKind.Producer)
                        && s.Parent == null)
            .ToList();

        Assert.Empty(orphanClientSpans);
    }

    [Fact]
    public async Task ErrorSpansHaveDescription()
    {
        await Assert.ThrowsAsync<Exception>(() => _service.CreateOrderAsync(null));

        var errorSpans = _telemetry.FinishedActivities
            .Where(s => s.Status == ActivityStatusCode.Error)
            .ToList();

        foreach (var span in errorSpans)
        {
            Assert.NotNull(span.StatusDescription);
            Assert.NotEmpty(span.StatusDescription);
        }
    }

    [Fact]
    public async Task SpanNamesAreTemplates()
    {
        await _service.CreateOrderAsync(new Order { Item = "widget", UserId = "user-123" });

        var uuidPattern = new Regex(@"[0-9a-f]{8}-[0-9a-f]{4}");
        var numericIdPattern = new Regex(@"/\d+");

        foreach (var span in _telemetry.FinishedActivities)
        {
            Assert.False(uuidPattern.IsMatch(span.DisplayName),
                $"Span '{span.DisplayName}' contains UUID — use template");
            Assert.False(numericIdPattern.IsMatch(span.DisplayName),
                $"Span '{span.DisplayName}' contains numeric ID — use template");
        }
    }
}
```
