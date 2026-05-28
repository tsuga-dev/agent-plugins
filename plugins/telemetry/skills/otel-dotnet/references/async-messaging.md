# Async Messaging — .NET OTel

> **Last verified:** 2026-03-23 | SDK: OpenTelemetry NuGet 1.15.x / .NET 8+

## Context Model: Use Span Links, Not Parent-Child

Async CONSUMER spans must use **span Links** to the producer span — not parent-child relationships. The producer and consumer are separate operations in separate traces.

```csharp
// BAD — makes consumer appear as a child of the producer's HTTP request
using var activity = _activitySource.StartActivity(
    "kafka.process",
    ActivityKind.Consumer,
    parentContext.ActivityContext   // sets producer as parent — WRONG
);

// GOOD — new root span with a Link back to the producer trace
// Pass links at creation time (works on .NET 8+; activity?.AddLink() requires .NET 9+)
var links = producerContext.ActivityContext.IsValid()
    ? new[] { new ActivityLink(producerContext.ActivityContext) }
    : Array.Empty<ActivityLink>();

using var activity = _activitySource.StartActivity(
    "receive orders",
    ActivityKind.Consumer,
    parentContext: default,
    tags: null,
    links: links
);
```

## Span Naming

Pattern: `{operation} {destination}` — e.g., `publish orders`, `receive payments`, `process user-events`

| BAD | GOOD |
|-----|------|
| `kafkaConsumer` | `receive user-events` |
| `SendMessage` | `publish orders` |
| `ProcessJob` | `process payment-queue` |

## Required `messaging.*` Semconv Attributes

| Attribute | Required | Example |
|-----------|----------|---------|
| `messaging.system` | Yes | `kafka`, `rabbitmq`, `servicebus` |
| `messaging.destination.name` | Yes | `orders`, `user-events` |
| `messaging.operation` | Yes | `publish`, `receive`, `process` |
| `messaging.message.id` | Recommended | `"msg-abc-123"` |

> Check `otel-semantic-conventions` for the full `messaging.*` namespace before adding custom attributes.

## Auto-Instrumentation Coverage

| System | Auto-instrumented? | Notes |
|--------|--------------------|-------|
| Kafka (Confluent.Kafka) | No | Manual instrumentation required |
| RabbitMQ (RabbitMQ.Client) | No | Manual instrumentation required |
| Azure Service Bus | Partial | `Azure.Messaging.ServiceBus` has built-in distributed tracing support |
| MassTransit | Yes | MassTransit propagates context automatically via message headers |

For systems without auto-instrumentation, use the patterns below.

## Kafka — Manual Propagation (Confluent.Kafka)

### Producer

```csharp
using Confluent.Kafka;
using OpenTelemetry;
using OpenTelemetry.Context.Propagation;
using System.Diagnostics;

private static readonly TextMapPropagator _propagator = Propagators.DefaultTextMapPropagator;
private static readonly ActivitySource _activitySource = new ActivitySource("my-service");

public async Task ProduceAsync(IProducer<string, string> producer, string topic, string value)
{
    using var activity = _activitySource.StartActivity("publish " + topic, ActivityKind.Producer);
    activity?.SetTag("messaging.system", "kafka");
    activity?.SetTag("messaging.destination.name", topic);
    activity?.SetTag("messaging.operation", "publish");

    var headers = new Headers();

    // Inject current trace context into Kafka message headers
    _propagator.Inject(
        new PropagationContext(Activity.Current?.Context ?? default, Baggage.Current),
        headers,
        (hdrs, key, val) => hdrs.Add(key, System.Text.Encoding.UTF8.GetBytes(val))
    );

    await producer.ProduceAsync(topic, new Message<string, string>
    {
        Key = Guid.NewGuid().ToString(),
        Value = value,
        Headers = headers
    });
}
```

### Consumer

```csharp
public void ProcessMessage(ConsumeResult<string, string> result)
{
    // Extract producer context from Kafka headers
    var producerContext = _propagator.Extract(
        default,
        result.Message.Headers,
        (headers, key) =>
        {
            var header = headers.FirstOrDefault(h => h.Key == key);
            return header == null
                ? Array.Empty<string>()
                : new[] { System.Text.Encoding.UTF8.GetString(header.GetValueBytes()) };
        }
    );

    // GOOD — new root span with Link back to producer; do NOT set parent
    // Pass links at creation time (.NET 8+); activity?.AddLink() requires .NET 9+
    var links = producerContext.ActivityContext.IsValid()
        ? new[] { new ActivityLink(producerContext.ActivityContext) }
        : Array.Empty<ActivityLink>();

    using var activity = _activitySource.StartActivity(
        "receive " + result.Topic,
        ActivityKind.Consumer,
        parentContext: default,
        tags: null,
        links: links
    );
    activity?.SetTag("messaging.system", "kafka");
    activity?.SetTag("messaging.destination.name", result.Topic);
    activity?.SetTag("messaging.operation", "receive");

    try
    {
        HandleMessage(result.Message.Value);
    }
    catch (Exception ex)
    {
        activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
        activity?.RecordException(ex);
        throw;
    }
}
```

## RabbitMQ — Manual Propagation (RabbitMQ.Client)

### Producer

```csharp
using RabbitMQ.Client;
using System.Diagnostics;

public void Publish(IModel channel, string exchange, string routingKey, byte[] body)
{
    using var activity = _activitySource.StartActivity("publish " + routingKey, ActivityKind.Producer);
    activity?.SetTag("messaging.system", "rabbitmq");
    activity?.SetTag("messaging.destination.name", routingKey);
    activity?.SetTag("messaging.operation", "publish");

    var props = channel.CreateBasicProperties();
    props.Headers = new Dictionary<string, object>();

    _propagator.Inject(
        new PropagationContext(Activity.Current?.Context ?? default, Baggage.Current),
        props.Headers,
        (headers, key, value) => headers[key] = value
    );

    channel.BasicPublish(exchange, routingKey, props, body);
}
```

### Consumer

```csharp
public void HandleDelivery(BasicDeliverEventArgs ea, IModel channel)
{
    var headers = ea.BasicProperties?.Headers ?? new Dictionary<string, object>();

    var producerContext = _propagator.Extract(
        default,
        headers,
        (hdrs, key) =>
        {
            if (hdrs.TryGetValue(key, out var val))
            {
                return val is byte[] bytes
                    ? new[] { System.Text.Encoding.UTF8.GetString(bytes) }
                    : new[] { val?.ToString() ?? string.Empty };
            }
            return Array.Empty<string>();
        }
    );

    // GOOD — new root span with Link to producer; do NOT set parent
    // Pass links at creation time (.NET 8+); activity?.AddLink() requires .NET 9+
    var links = producerContext.ActivityContext.IsValid()
        ? new[] { new ActivityLink(producerContext.ActivityContext) }
        : Array.Empty<ActivityLink>();

    using var activity = _activitySource.StartActivity(
        "receive " + ea.RoutingKey,
        ActivityKind.Consumer,
        parentContext: default,
        tags: null,
        links: links
    );
    activity?.SetTag("messaging.system", "rabbitmq");
    activity?.SetTag("messaging.destination.name", ea.RoutingKey);
    activity?.SetTag("messaging.operation", "receive");

    ProcessDelivery(ea.Body.ToArray());
}
```

## Azure Service Bus

`Azure.Messaging.ServiceBus` (v7.x) has built-in distributed tracing support and propagates context automatically. For services using raw `ApplicationProperties`, follow the pattern below.

### Producer (manual context injection)

```csharp
using Azure.Messaging.ServiceBus;

public async Task SendAsync(ServiceBusSender sender, string body)
{
    using var activity = _activitySource.StartActivity("publish " + sender.EntityPath, ActivityKind.Producer);
    activity?.SetTag("messaging.system", "servicebus");
    activity?.SetTag("messaging.destination.name", sender.EntityPath);
    activity?.SetTag("messaging.operation", "publish");

    var message = new ServiceBusMessage(body);

    _propagator.Inject(
        new PropagationContext(Activity.Current?.Context ?? default, Baggage.Current),
        message.ApplicationProperties,
        (props, key, value) => props[key] = value
    );

    await sender.SendMessageAsync(message);
}
```

### Consumer

```csharp
public async Task ProcessMessageAsync(ServiceBusReceivedMessage message, string queueName)
{
    var producerContext = _propagator.Extract(
        default,
        message.ApplicationProperties,
        (props, key) => props.TryGetValue(key, out var value)
            ? new[] { value?.ToString() ?? string.Empty }
            : Array.Empty<string>()
    );

    // GOOD — new root span with Link to producer
    // Pass links at creation time (.NET 8+); activity?.AddLink() requires .NET 9+
    var links = producerContext.ActivityContext.IsValid()
        ? new[] { new ActivityLink(producerContext.ActivityContext) }
        : Array.Empty<ActivityLink>();

    using var activity = _activitySource.StartActivity(
        "receive " + queueName,
        ActivityKind.Consumer,
        parentContext: default,
        tags: null,
        links: links
    );
    activity?.SetTag("messaging.system", "servicebus");
    activity?.SetTag("messaging.destination.name", queueName);
    activity?.SetTag("messaging.operation", "receive");

    await HandleMessageAsync(message);
}
```

## Verification

```bash
# Check producer spans
tsuga spans search --query "context.service.name:<producer-service> messaging.system:kafka" --max-results 5

# Check consumer spans and Links field
tsuga spans search --query "context.service.name:<consumer-service> messaging.operation:receive" --max-results 5
```
