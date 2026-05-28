# Distributed Context Propagation — C++

> **Last verified:** 2026-03-23 | SDK: `opentelemetry-cpp` 1.26.0

> **Async messaging propagation (Kafka, AMQP, SQS):** See [async-messaging.md](async-messaging.md) for MapCarrier patterns, span Links, and semconv attributes.

## Overview

Trace context must be explicitly propagated across service boundaries. The W3C TraceContext headers (`traceparent`, `tracestate`) carry the trace ID and span ID between services. The C++ SDK provides text map propagators that extract and inject context from/into carrier objects (HTTP headers, gRPC metadata). There is no auto-instrumentation for any transport — all carriers must be implemented manually.

## Setup: Configure the Global Propagator

Set up the W3C TraceContext propagator once in `InitTelemetry()`. Without this call, `Extract()` and `Inject()` are no-ops and traces will not link across services.

```cpp
#include "opentelemetry/context/propagation/global_propagator.h"
#include "opentelemetry/trace/propagation/http_trace_context.h"

// In InitTelemetry():
opentelemetry::context::propagation::GlobalTextMapPropagator::SetGlobalPropagator(
    opentelemetry::nostd::shared_ptr<opentelemetry::context::propagation::TextMapPropagator>(
        new opentelemetry::trace::propagation::HttpTraceContext()
    )
);
```

## Inbound: Server Context Extraction

Implement a `TextMapCarrier` adapter for your transport type. The adapter reads header values from the inbound request.

### HTTP (cpp-httplib)

```cpp
#include "opentelemetry/context/propagation/global_propagator.h"
#include "opentelemetry/context/propagation/text_map_propagator.h"
#include "opentelemetry/context/runtime_context.h"
#include "opentelemetry/trace/provider.h"

namespace context_api = opentelemetry::context;
namespace propagation = opentelemetry::context::propagation;
namespace trace_api   = opentelemetry::trace;

// Carrier adapter for httplib headers (read-only extract)
class HttplibHeaderCarrier : public propagation::TextMapCarrier {
    const httplib::Headers& headers_;
public:
    explicit HttplibHeaderCarrier(const httplib::Headers& h) : headers_(h) {}

    opentelemetry::nostd::string_view Get(
        opentelemetry::nostd::string_view key) const noexcept override {
        auto it = headers_.find(std::string(key));
        if (it != headers_.end()) return it->second;
        return "";
    }

    void Set(opentelemetry::nostd::string_view,
             opentelemetry::nostd::string_view) noexcept override {}  // read-only
};

// In request handler:
svr.Get("/users/:id", [](const httplib::Request& req, httplib::Response& res) {
    HttplibHeaderCarrier carrier(req.headers);
    auto parent_ctx = propagation::GlobalTextMapPropagator::GetGlobalPropagator()
        ->Extract(carrier, context_api::RuntimeContext::GetCurrent());

    trace_api::StartSpanOptions options;
    options.parent = parent_ctx;
    options.kind   = trace_api::SpanKind::kServer;

    auto tracer = trace_api::Provider::GetTracerProvider()->GetTracer("my-app", "1.0.0");
    auto span   = tracer->StartSpan("GET /users/{id}", {}, options);
    auto scope  = tracer->WithActiveSpan(span);

    // ... handle request ...
    span->End();
});
```

### gRPC Server

```cpp
#include "opentelemetry/context/propagation/global_propagator.h"
#include <grpcpp/grpcpp.h>

class GrpcMetadataCarrier : public opentelemetry::context::propagation::TextMapCarrier {
    const grpc::ServerContext* ctx_;
public:
    explicit GrpcMetadataCarrier(const grpc::ServerContext* ctx) : ctx_(ctx) {}

    opentelemetry::nostd::string_view Get(
        opentelemetry::nostd::string_view key) const noexcept override {
        auto it = ctx_->client_metadata().find(
            grpc::string_ref(key.data(), key.size()));
        if (it != ctx_->client_metadata().end())
            return opentelemetry::nostd::string_view(it->second.data(), it->second.size());
        return "";
    }

    void Set(opentelemetry::nostd::string_view,
             opentelemetry::nostd::string_view) noexcept override {}
};

// In gRPC handler:
grpc::Status GetUser(grpc::ServerContext* ctx, const Request* req, Response* reply) override {
    GrpcMetadataCarrier carrier(ctx);
    auto parent_ctx = opentelemetry::context::propagation::GlobalTextMapPropagator
        ::GetGlobalPropagator()
        ->Extract(carrier, opentelemetry::context::RuntimeContext::GetCurrent());

    opentelemetry::trace::StartSpanOptions options;
    options.parent = parent_ctx;
    options.kind   = opentelemetry::trace::SpanKind::kServer;

    auto tracer = opentelemetry::trace::Provider::GetTracerProvider()->GetTracer("my-app");
    auto span   = tracer->StartSpan("grpc.server.GetUser", {}, options);
    auto scope  = tracer->WithActiveSpan(span);

    // ... process ...
    span->End();
    return grpc::Status::OK;
}
```

## Outbound: Client Context Injection

Implement a mutable carrier that writes headers into the outbound request.

### HTTP (cpp-httplib client)

```cpp
class HttplibMutableCarrier : public opentelemetry::context::propagation::TextMapCarrier {
    httplib::Headers& headers_;
public:
    explicit HttplibMutableCarrier(httplib::Headers& h) : headers_(h) {}

    opentelemetry::nostd::string_view Get(
        opentelemetry::nostd::string_view) const noexcept override { return ""; }

    void Set(opentelemetry::nostd::string_view key,
             opentelemetry::nostd::string_view value) noexcept override {
        headers_.emplace(std::string(key), std::string(value));
    }
};

void CallDownstream(const std::string& host, const std::string& path) {
    httplib::Headers headers;
    HttplibMutableCarrier carrier(headers);
    opentelemetry::context::propagation::GlobalTextMapPropagator::GetGlobalPropagator()
        ->Inject(carrier, opentelemetry::context::RuntimeContext::GetCurrent());

    httplib::Client cli(host);
    auto result = cli.Get(path, headers);
}
```

### gRPC Client

gRPC metadata keys must be lowercase. W3C `traceparent` and `tracestate` are already lowercase per spec.

```cpp
class GrpcClientMetadataCarrier : public opentelemetry::context::propagation::TextMapCarrier {
    grpc::ClientContext* ctx_;
public:
    explicit GrpcClientMetadataCarrier(grpc::ClientContext* ctx) : ctx_(ctx) {}

    opentelemetry::nostd::string_view Get(
        opentelemetry::nostd::string_view) const noexcept override { return ""; }

    void Set(opentelemetry::nostd::string_view key,
             opentelemetry::nostd::string_view value) noexcept override {
        ctx_->AddMetadata(std::string(key), std::string(value));
    }
};

grpc::ClientContext grpc_ctx;
GrpcClientMetadataCarrier carrier(&grpc_ctx);
opentelemetry::context::propagation::GlobalTextMapPropagator::GetGlobalPropagator()
    ->Inject(carrier, opentelemetry::context::RuntimeContext::GetCurrent());

auto status = stub_->GetUser(&grpc_ctx, request, &reply);
```

## Anti-Pattern: Do Not Merge Separate Workflows

```cpp
// WRONG — sets parent to producer context; consumer appears as child of producer trace
opentelemetry::trace::StartSpanOptions opts;
opts.parent = extracted_producer_context;
auto span = tracer->StartSpan("process.job", {}, opts);

// CORRECT — new root span; producer context stored as link attributes
opentelemetry::trace::StartSpanOptions opts;
opts.kind = opentelemetry::trace::SpanKind::kConsumer;
// opts.parent NOT set — this is a new root
auto span = tracer->StartSpan("process job", {
    {"messaging.producer.trace_id", producer_trace_id_hex},
    {"messaging.producer.span_id",  producer_span_id_hex},
}, opts);
```

## Configuring Propagators

Default: W3C TraceContext (`traceparent`, `tracestate`). To add B3 support for Zipkin interop, compose propagators at init:

```cpp
#include "opentelemetry/trace/propagation/b3_propagator.h"

// Multi-format composite propagator
// CompositePropagator takes a std::vector<std::unique_ptr<TextMapPropagator>>.
// Build the vector and move elements into it — initializer_list of unique_ptr is not supported.
std::vector<std::unique_ptr<propagation::TextMapPropagator>> propagators;
propagators.push_back(std::make_unique<opentelemetry::trace::propagation::HttpTraceContext>());
propagators.push_back(std::make_unique<opentelemetry::trace::propagation::B3PropagatorMultiHeader>());

auto composite = opentelemetry::nostd::shared_ptr<propagation::TextMapPropagator>(
    new opentelemetry::context::propagation::CompositePropagator(std::move(propagators))
);
propagation::GlobalTextMapPropagator::SetGlobalPropagator(composite);
```

Use W3C TraceContext for all new services. Add B3 only when interoperating with Zipkin-instrumented services or Istio/Envoy meshes configured for B3.

## Tsuga Trace Continuity Validation

After instrumenting propagation, verify parent/child linkage:

```bash
tsuga spans search --query "context.service.name:<caller-service>" --max-results 5
# Note traceId values from results
tsuga spans search --query "context.service.name:<callee-service> traceId:<trace-id>"
# parentSpanId on callee spans must match spanId from caller spans
```
