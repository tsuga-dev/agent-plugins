# Async Messaging — C++ OTel

> **Last verified:** 2026-03-23 | SDK: `opentelemetry-cpp` 1.26.0

## Context Model: Use span Links, Not Parent-Child

Async CONSUMER spans must use **span Links** to the producer span — not parent-child relationships. The producer and consumer are separate operations in separate traces.

```cpp
// BAD — makes consumer appear as a child of the producer HTTP request
opentelemetry::trace::StartSpanOptions opts;
opts.parent = extracted_producer_context;   // DO NOT set parent to producer context
auto span = tracer->StartSpan("receive orders", opts);

// GOOD — new root span linked to producer for cross-trace navigation
opentelemetry::trace::StartSpanOptions opts;
opts.kind = opentelemetry::trace::SpanKind::kConsumer;
// Do NOT set opts.parent — leave as default (empty = new root)
auto producer_span_ctx = opentelemetry::trace::GetSpan(extracted_producer_context)
    ->GetContext();

// Links are passed as a separate parameter to StartSpan(name, attributes, links, options).
// Alternatively, record producer trace_id/span_id as span attributes (see examples below).
auto span = tracer->StartSpan("receive orders", {}, opts);
span->AddLink(producer_span_ctx, {});  // AddLink available in ABI v2+
```

> **C++ Links API note:** In `opentelemetry-cpp`, span Links are passed as a separate parameter to `StartSpan()` — there is no `StartSpanOptions::links` field. Use the `StartSpan(name, attributes, links, options)` overload, passing links as a `std::vector` of `std::pair<SpanContext, KeyValueIterable>`. If a simpler fallback is preferred, record the producer `trace_id` and `span_id` as span attributes (`messaging.producer.trace_id`, `messaging.producer.span_id`).

## Span Naming

Pattern: `{operation} {destination}` — e.g., `publish orders`, `receive payments`, `process user-events`

| BAD | GOOD |
|-----|------|
| `kafkaConsumer` | `receive user-events` |
| `sendMessage` | `publish orders` |
| `processJob` | `process payment-queue` |

## Required `messaging.*` Semconv Attributes

| Attribute | Required | Example |
|-----------|----------|---------|
| `messaging.system` | Yes | `kafka`, `rabbitmq`, `aws_sqs` |
| `messaging.destination.name` | Yes | `orders`, `user-events` |
| `messaging.operation` | Yes | `publish`, `receive`, `process` |
| `messaging.message.id` | Recommended | `"msg-abc-123"` |

> Check `otel-semantic-conventions` for the full `messaging.*` namespace before adding custom attributes.

## Auto-Instrumentation Coverage

| System | Auto-instrumented? |
|--------|-------------------|
| Kafka (librdkafka) | No — manual only |
| RabbitMQ / AMQP (amqp-cpp) | No — manual only |
| AWS SQS (aws-sdk-cpp) | No — manual only |
| Any other messaging | No — manual only |

C++ has no agent or plugin-based auto-instrumentation for messaging. All inject/extract is manual.

## MapCarrier — Reusable Carrier for Message Headers

All messaging examples below use a `MapCarrier` backed by `std::map<std::string, std::string>`. Define it once and reuse:

```cpp
#include "opentelemetry/context/propagation/text_map_propagator.h"
#include <map>
#include <string>

class MapCarrier : public opentelemetry::context::propagation::TextMapCarrier {
    std::map<std::string, std::string>& map_;
public:
    explicit MapCarrier(std::map<std::string, std::string>& m) : map_(m) {}

    opentelemetry::nostd::string_view Get(
        opentelemetry::nostd::string_view key) const noexcept override {
        auto it = map_.find(std::string(key));
        return it != map_.end() ? opentelemetry::nostd::string_view(it->second) : "";
    }

    void Set(opentelemetry::nostd::string_view key,
             opentelemetry::nostd::string_view value) noexcept override {
        map_[std::string(key)] = std::string(value);
    }
};
```

## Kafka — Manual Propagation (librdkafka)

### Producer

```cpp
#include "opentelemetry/context/propagation/global_propagator.h"
#include "opentelemetry/context/runtime_context.h"
#include <librdkafka/rdkafkacpp.h>
#include <map>

namespace propagation = opentelemetry::context::propagation;

// Inject context into a string map, then copy to Kafka message headers
std::map<std::string, std::string> header_map;
MapCarrier carrier(header_map);
propagation::GlobalTextMapPropagator::GetGlobalPropagator()
    ->Inject(carrier, opentelemetry::context::RuntimeContext::GetCurrent());

// Create Kafka message with injected headers
std::unique_ptr<RdKafka::Headers> headers(RdKafka::Headers::create());
for (const auto& [key, value] : header_map) {
    headers->add(key, value.data(), value.size());
}

// Attach headers to the produced message
// producer->produce(...) — set headers on the message
```

### Consumer

```cpp
#include "opentelemetry/trace/provider.h"
#include "opentelemetry/context/propagation/global_propagator.h"
#include "opentelemetry/context/runtime_context.h"
#include <librdkafka/rdkafkacpp.h>
#include <map>

namespace trace_api   = opentelemetry::trace;
namespace propagation = opentelemetry::context::propagation;

// Extract headers from consumed message into a map
std::map<std::string, std::string> header_map;
RdKafka::Headers* msg_headers = message->headers();
if (msg_headers) {
    for (const auto& header : msg_headers->get_all()) {
        header_map[header.key()] = std::string(
            static_cast<const char*>(header.value()), header.value_size());
    }
}

MapCarrier carrier(header_map);
auto extracted_ctx = propagation::GlobalTextMapPropagator::GetGlobalPropagator()
    ->Extract(carrier, opentelemetry::context::RuntimeContext::GetCurrent());

// GOOD — new root span with Link to producer; do NOT set parent
auto producer_span_ctx = trace_api::GetSpan(extracted_ctx)->GetContext();

trace_api::StartSpanOptions opts;
opts.kind = trace_api::SpanKind::kConsumer;
// opts.parent NOT set — this is a new root span

auto tracer = trace_api::Provider::GetTracerProvider()->GetTracer("my-app", "1.0.0");
auto span   = tracer->StartSpan(
    "receive " + std::string(message->topic_name()),
    {
        {"messaging.system",           "kafka"},
        {"messaging.destination.name", message->topic_name()},
        {"messaging.operation",        "receive"},
        // Fallback link attributes (or use the StartSpan links parameter overload)
        {"messaging.producer.trace_id", TraceIdToHex(producer_span_ctx.trace_id())},
        {"messaging.producer.span_id",  SpanIdToHex(producer_span_ctx.span_id())},
    },
    opts
);
auto scope = tracer->WithActiveSpan(span);

try {
    ProcessMessage(message);
    span->End();
} catch (const std::exception& e) {
    span->AddEvent("exception", {{"exception.type", typeid(e).name()},
                                  {"exception.message", e.what()}});
    span->SetStatus(trace_api::StatusCode::kError, e.what());
    span->End();
    throw;
}
```

## RabbitMQ / AMQP — Manual Propagation

### Producer (inject into message properties)

```cpp
// Build header map
std::map<std::string, std::string> header_map;
MapCarrier carrier(header_map);
propagation::GlobalTextMapPropagator::GetGlobalPropagator()
    ->Inject(carrier, opentelemetry::context::RuntimeContext::GetCurrent());

// Copy header_map to your AMQP library's message properties map
// (amqp-cpp, SimpleAmqpClient, etc. — each has its own header type)
AMQP::Table amqp_headers;
for (const auto& [key, value] : header_map) {
    amqp_headers[key] = value;
}
```

### Consumer (extract from message properties)

```cpp
// Convert AMQP headers to std::map
std::map<std::string, std::string> header_map;
for (const auto& [key, value] : amqp_message.headers) {
    header_map[key] = static_cast<std::string>(value);
}

MapCarrier carrier(header_map);
auto extracted_ctx = propagation::GlobalTextMapPropagator::GetGlobalPropagator()
    ->Extract(carrier, opentelemetry::context::RuntimeContext::GetCurrent());

auto producer_span_ctx = trace_api::GetSpan(extracted_ctx)->GetContext();

// GOOD — new root span; producer context stored as link attributes
trace_api::StartSpanOptions opts;
opts.kind = trace_api::SpanKind::kConsumer;
auto span = tracer->StartSpan(
    "receive " + queue_name,
    {
        {"messaging.system",           "rabbitmq"},
        {"messaging.destination.name", queue_name},
        {"messaging.operation",        "receive"},
        {"messaging.producer.trace_id", TraceIdToHex(producer_span_ctx.trace_id())},
        {"messaging.producer.span_id",  SpanIdToHex(producer_span_ctx.span_id())},
    },
    opts
);
auto scope = tracer->WithActiveSpan(span);
// ... process message ...
span->End();
```

## AWS SQS — Manual Propagation (aws-sdk-cpp)

### Producer (inject into MessageAttributes)

```cpp
#include <aws/sqs/SQSClient.h>
#include <aws/sqs/model/SendMessageRequest.h>
#include <map>

std::map<std::string, std::string> header_map;
MapCarrier carrier(header_map);
propagation::GlobalTextMapPropagator::GetGlobalPropagator()
    ->Inject(carrier, opentelemetry::context::RuntimeContext::GetCurrent());

Aws::SQS::Model::SendMessageRequest request;
request.SetQueueUrl(queue_url);
request.SetMessageBody(body);

// Inject trace headers as SQS MessageAttributes
for (const auto& [key, value] : header_map) {
    Aws::SQS::Model::MessageAttributeValue attr;
    attr.SetDataType("String");
    attr.SetStringValue(value);
    request.AddMessageAttributes(key, attr);
}
sqs_client->SendMessage(request);
```

### Consumer (extract from MessageAttributes)

```cpp
std::map<std::string, std::string> header_map;
for (const auto& [key, attr] : sqs_message.GetMessageAttributes()) {
    header_map[key] = attr.GetStringValue();
}

MapCarrier carrier(header_map);
auto extracted_ctx = propagation::GlobalTextMapPropagator::GetGlobalPropagator()
    ->Extract(carrier, opentelemetry::context::RuntimeContext::GetCurrent());

auto producer_span_ctx = trace_api::GetSpan(extracted_ctx)->GetContext();

// GOOD — new root span; producer context as link attributes
trace_api::StartSpanOptions opts;
opts.kind = trace_api::SpanKind::kConsumer;
auto span = tracer->StartSpan(
    "receive " + queue_name,
    {
        {"messaging.system",           "aws_sqs"},
        {"messaging.destination.name", queue_name},
        {"messaging.operation",        "receive"},
        {"messaging.producer.trace_id", TraceIdToHex(producer_span_ctx.trace_id())},
        {"messaging.producer.span_id",  SpanIdToHex(producer_span_ctx.span_id())},
    },
    opts
);
auto scope = tracer->WithActiveSpan(span);
// ... process message ...
span->End();
```

## Helper: Hex Conversion

```cpp
#include <array>
#include <string>
#include "opentelemetry/trace/span_context.h"

std::string TraceIdToHex(const opentelemetry::trace::TraceId& trace_id) {
    std::array<char, 33> buf{};
    trace_id.ToLowerBase16(buf);
    buf[32] = '\0';
    return std::string(buf.data());
}

std::string SpanIdToHex(const opentelemetry::trace::SpanId& span_id) {
    std::array<char, 17> buf{};
    span_id.ToLowerBase16(buf);
    buf[16] = '\0';
    return std::string(buf.data());
}
```

## Verification

```bash
# Check producer spans
tsuga spans search --query "context.service.name:<producer-service> messaging.system:kafka" --max-results 5

# Check consumer spans and link attributes
tsuga spans search --query "context.service.name:<consumer-service> messaging.operation:receive" --max-results 5
```
