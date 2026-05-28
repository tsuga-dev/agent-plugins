# Auto-Instrumentation — C++

> **Note:** C++ has no zero-code auto-instrumentation equivalent to the Java agent. There is no agent, no bytecode patching, and no framework plugin path. All instrumentation in C++ is manual — every span, metric, and log record must be created explicitly via the OTel C++ API. This file documents library-level patterns that reduce the amount of manual instrumentation needed.

## Overview

C++ does not support runtime bytecode injection. "Auto-instrumentation" in C++ means using instrumentation-aware libraries, middleware wrappers, and RAII span guards that minimize manual span placement. The OpenTelemetry C++ SDK provides no automatic patching — all instrumentation is library-level or explicit.

## What the C++ SDK Provides

- **Factory-based initialization** of TracerProvider and MeterProvider
- **RAII span scope guards** via `tracer->WithActiveSpan(span)`
- **Stable Logs API** since v1.16.0 (current: v1.26.0)
- **Batch and Simple span processors**

There is no equivalent of Java's `-javaagent` or Python's `opentelemetry-instrument` command.

## HTTP Framework Integration

### cpp-httplib (server)

cpp-httplib does not provide OTel middleware. Add a pre-route handler:

```cpp
#include "httplib.h"
#include "opentelemetry/trace/provider.h"
#include "opentelemetry/context/runtime_context.h"

namespace trace_api = opentelemetry::trace;

void StartRequestSpan(
    const httplib::Request& req,
    httplib::Response& res,
    opentelemetry::nostd::shared_ptr<trace_api::Span>& out_span,
    opentelemetry::trace::Scope& out_scope
) {
    auto tracer = trace_api::Provider::GetTracerProvider()
        ->GetTracer("my-app", "1.0.0");

    // Extract W3C TraceContext from incoming headers
    // (requires opentelemetry-http header extractor — see propagation.md)
    auto span = tracer->StartSpan("http.server",
        {{"http.method", req.method},
         {"http.target", req.target},
         {"http.scheme", "http"}});

    out_scope = tracer->WithActiveSpan(span);
    out_span  = span;
}

int main() {
    InitTelemetry();

    httplib::Server svr;

    svr.Get("/users/:id", [](const httplib::Request& req, httplib::Response& res) {
        auto tracer = trace_api::Provider::GetTracerProvider()
            ->GetTracer("my-app", "1.0.0");

        auto span  = tracer->StartSpan("get.user",
            {{"user.id", req.path_params.at("id")}});
        auto scope = tracer->WithActiveSpan(span);

        try {
            auto user = GetUser(req.path_params.at("id"));
            res.set_content(user.ToJson(), "application/json");
            span->SetStatus(trace_api::StatusCode::kOk);
        } catch (const std::exception& e) {
            span->AddEvent("exception", {{"exception.type", typeid(e).name()},
                                      {"exception.message", e.what()}});
            span->SetStatus(trace_api::StatusCode::kError, e.what());
            res.status = 500;
        }
        span->End();
    });

    svr.listen("0.0.0.0", 8080);
    ShutdownTelemetry();
    return 0;
}
```

### gRPC Server

gRPC for C++ supports interceptors. Add an OTel interceptor to the server:

```cpp
#include <grpcpp/grpcpp.h>
#include "opentelemetry/trace/provider.h"

namespace trace_api = opentelemetry::trace;

class OtelServerInterceptor : public grpc::ServerInterceptorFactoryInterface {
public:
    grpc::experimental::Interceptor* CreateServerInterceptor(
        grpc::experimental::ServerRpcInfo* info) override;
};

class OtelInterceptor : public grpc::experimental::Interceptor {
    opentelemetry::nostd::shared_ptr<trace_api::Span> span_;
    opentelemetry::trace::Scope scope_;

public:
    void Intercept(grpc::experimental::InterceptorBatchMethods* methods) override {
        if (methods->QueryInterceptionHookPoint(
                grpc::experimental::InterceptionHookPoints::PRE_SEND_INITIAL_METADATA)) {
            auto tracer = trace_api::Provider::GetTracerProvider()
                ->GetTracer("my-app", "1.0.0");
            span_  = tracer->StartSpan("grpc.server");
            scope_ = tracer->WithActiveSpan(span_);
        }

        if (methods->QueryInterceptionHookPoint(
                grpc::experimental::InterceptionHookPoints::POST_RECV_STATUS)) {
            span_->End();
        }

        methods->Proceed();
    }
};
```

## RAII Pattern for Minimal Boilerplate

Define helper macros to reduce span boilerplate:

```cpp
#include "opentelemetry/trace/provider.h"

// Helper RAII wrapper
class SpanGuard {
    opentelemetry::nostd::shared_ptr<opentelemetry::trace::Span> span_;
    opentelemetry::trace::Scope scope_;
    bool ended_ = false;

public:
    SpanGuard(const std::string& name,
              const opentelemetry::common::KeyValueIterable& attrs = {}) {
        auto tracer = opentelemetry::trace::Provider::GetTracerProvider()
            ->GetTracer("my-app", "1.0.0");
        span_  = tracer->StartSpan(name, attrs);
        scope_ = tracer->WithActiveSpan(span_);
    }

    opentelemetry::trace::Span* operator->() { return span_.get(); }

    void End() {
        if (!ended_) { span_->End(); ended_ = true; }
    }

    ~SpanGuard() { End(); }
};

// Usage — minimal boilerplate
void ProcessOrder(const Order& order) {
    SpanGuard span("order.process",
        {{"order.id", order.id}, {"order.items", (int64_t)order.items.size()}});

    ValidateOrder(order);
    PersistOrder(order);
    // span->End() called automatically on scope exit
}
```

## What the Logs API Covers

The C++ Logs API is **stable since v1.16.0**. Use it for structured logging:

```cpp
#include "opentelemetry/logs/provider.h"

namespace logs_api = opentelemetry::logs;

auto logger = logs_api::Provider::GetLoggerProvider()->GetLogger("my-app");
logger->Info("user.login", {{"user.id", userId}, {"success", true}});
logger->Error("payment.failed", {{"order.id", orderId}, {"error", errorMsg}});
```

Or integrate with spdlog (see SKILL.md trace-log correlation section).

## CMake / vcpkg Setup

```cmake
find_package(opentelemetry-cpp CONFIG REQUIRED)

target_link_libraries(my-app
    opentelemetry-cpp::api
    opentelemetry-cpp::sdk
    opentelemetry-cpp::otlp_grpc_exporter
    opentelemetry-cpp::otlp_http_exporter
    opentelemetry-cpp::metrics
    opentelemetry-cpp::logs
)
```

Install via vcpkg:

```bash
vcpkg install opentelemetry-cpp
# or with specific features
vcpkg install "opentelemetry-cpp[otlp-grpc,metrics,logs]"
```

## Verifying Instrumentation Is Active

```bash
tsuga spans search --query "context.service.name:my-app" --max-results 5
# Look for manual span names from your SpanGuard wrappers
```
