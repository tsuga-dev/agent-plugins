# Framework-Specific Recipes — C++

## gRPC (Server and Client)

gRPC C++ supports interceptors for both server and client. The OTel SDK provides OTLP/gRPC exporters; for service-level gRPC instrumentation, use interceptors.

### Server Interceptor

```cpp
#include <grpcpp/grpcpp.h>
#include <grpcpp/support/interceptor.h>
#include "opentelemetry/trace/provider.h"
#include "opentelemetry/context/propagation/global_propagator.h"
#include "opentelemetry/context/runtime_context.h"

namespace trace_api = opentelemetry::trace;
namespace prop      = opentelemetry::context::propagation;

class OtelServerInterceptor : public grpc::experimental::Interceptor {
    opentelemetry::nostd::shared_ptr<trace_api::Span> span_;
    opentelemetry::trace::Scope scope_;

public:
    void Intercept(grpc::experimental::InterceptorBatchMethods* methods) override {
        if (methods->QueryInterceptionHookPoint(
                grpc::experimental::InterceptionHookPoints::PRE_SEND_INITIAL_METADATA)) {

            // Extract parent context from gRPC metadata
            auto* server_ctx = /* get grpc::ServerContext */;
            // (see propagation.md for GrpcMetadataCarrier)

            auto tracer = trace_api::Provider::GetTracerProvider()
                ->GetTracer("my-grpc-service", "1.0.0");
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

class OtelServerInterceptorFactory
    : public grpc::experimental::ServerInterceptorFactoryInterface {
public:
    grpc::experimental::Interceptor* CreateServerInterceptor(
        grpc::experimental::ServerRpcInfo*) override {
        return new OtelServerInterceptor();
    }
};

// Register in server builder
grpc::experimental::ServerBuilder builder;
builder.experimental().SetInterceptorCreators({
    std::make_unique<OtelServerInterceptorFactory>()
});
```

### gRPC Service Handler Pattern

```cpp
#include "my_service.grpc.pb.h"
#include "opentelemetry/trace/provider.h"

namespace trace_api = opentelemetry::trace;

class MyServiceImpl final : public MyService::Service {
    opentelemetry::nostd::shared_ptr<trace_api::Tracer> tracer_;

public:
    MyServiceImpl()
        : tracer_(trace_api::Provider::GetTracerProvider()->GetTracer("my-service", "1.0.0")) {}

    grpc::Status GetUser(
        grpc::ServerContext* ctx,
        const GetUserRequest* request,
        GetUserResponse* response) override
    {
        auto span  = tracer_->StartSpan("get_user",
            {{"user.id", request->user_id()}});
        auto scope = tracer_->WithActiveSpan(span);

        try {
            auto user = db_.GetUser(request->user_id());
            response->set_id(user.id);
            response->set_name(user.name);
            span->SetStatus(trace_api::StatusCode::kOk);
            span->End();
            return grpc::Status::OK;
        } catch (const std::exception& e) {
            span->AddEvent("exception", {{"exception.type", typeid(e).name()},
                                      {"exception.message", e.what()}});
            span->SetStatus(trace_api::StatusCode::kError, e.what());
            span->End();
            return grpc::Status(grpc::StatusCode::INTERNAL, e.what());
        }
    }
};
```

## HTTP (cpp-httplib)

```cpp
#include "httplib.h"
#include "opentelemetry/trace/provider.h"

namespace trace_api = opentelemetry::trace;

int main() {
    InitTelemetry();

    httplib::Server svr;
    auto tracer = trace_api::Provider::GetTracerProvider()
        ->GetTracer("http-service", "1.0.0");

    svr.Get("/users/:id", [&tracer](const httplib::Request& req, httplib::Response& res) {
        auto span  = tracer->StartSpan("http.get_user",
            {{"http.method", "GET"},
             {"http.target", req.path},
             {"user.id", req.path_params.at("id")}});
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
            res.body   = R"({"error":"internal server error"})";
        }

        span->End();
    });

    svr.Get("/health", [](const httplib::Request&, httplib::Response& res) {
        res.set_content(R"({"status":"ok"})", "application/json");
    });

    svr.listen("0.0.0.0", 8080);
    ShutdownTelemetry();
    return 0;
}
```

## Span and Scope Lifecycle Rules

C++ requires explicit management of span lifetime. Critical rules:

```cpp
// Rule 1: Always call span->End() — even on exception paths
auto span  = tracer->StartSpan("op.name");
auto scope = tracer->WithActiveSpan(span);
try {
    doWork();
    span->SetStatus(trace_api::StatusCode::kOk);
    span->End();
} catch (const std::exception& e) {
    span->AddEvent("exception", {{"exception.type", typeid(e).name()},
                                      {"exception.message", e.what()}});
    span->SetStatus(trace_api::StatusCode::kError, e.what());
    span->End();   // REQUIRED in catch too
    throw;
}

// Rule 2: scope destructor deactivates span context — it does NOT end the span
// Both scope and span->End() are required

// Rule 3: span->End() can only be called once — it's idempotent after first call
// but the shared_ptr keeps the object alive; only End() records it

// Rule 4: Prefer RAII wrapper (see auto-instrumentation.md SpanGuard)
```

## SimpleSpanProcessor vs BatchSpanProcessor

```cpp
// SimpleSpanProcessor — synchronous, one export per span
// Use for: development, debugging, Lambda-like short-lived processes
auto simple_processor = trace_sdk::SimpleSpanProcessorFactory::Create(
    std::move(exporter)
);

// BatchSpanProcessor — async, buffered exports
// Use for: production, any server/long-running process
auto batch_processor = trace_sdk::BatchSpanProcessorFactory::Create(
    std::move(exporter), {}
);
```

> **Warning:** Never use `SimpleSpanProcessorFactory` in production — it blocks the calling thread on every span export.

## CMake Linking Summary

```cmake
target_link_libraries(my-app
    # Core
    opentelemetry-cpp::api
    opentelemetry-cpp::sdk

    # Exporters — choose one or both
    opentelemetry-cpp::otlp_grpc_exporter   # gRPC/port 4317
    opentelemetry-cpp::otlp_http_exporter   # HTTP/port 4318

    # Signals
    opentelemetry-cpp::metrics
    opentelemetry-cpp::logs

    # gRPC service (if using gRPC for your service, not just exporter)
    gRPC::grpc++
    protobuf::libprotobuf
)

## Lifecycle Logging

Structured log events correlated with OTel trace context.

```cpp
#include <opentelemetry/logs/provider.h>
#include <opentelemetry/trace/provider.h>
#include <opentelemetry/exporters/otlp/otlp_grpc_log_record_exporter_factory.h>
#include <opentelemetry/sdk/logs/logger_provider_factory.h>
#include <opentelemetry/sdk/logs/batch_log_record_processor_factory.h>

namespace logs_api = opentelemetry::logs;
namespace trace_api = opentelemetry::trace;

// Get OTel logger
auto logger = logs_api::Provider::GetLoggerProvider()->GetLogger("my-service");

// Helper: log with current trace context
void LogWithTrace(logs_api::Severity sev, std::string_view message,
                  std::initializer_list<std::pair<std::string, std::string>> attrs = {}) {
    auto record = logger->CreateLogRecord();
    record->SetSeverity(sev);
    record->SetBody(std::string(message));
    // Inject current trace context
    auto span_ctx = trace_api::GetSpan(opentelemetry::context::RuntimeContext::GetCurrent())->GetContext();
    if (span_ctx.IsValid()) {
        record->SetTraceId(span_ctx.trace_id());
        record->SetSpanId(span_ctx.span_id());
    }
    for (const auto& [k, v] : attrs) {
        record->SetAttribute(k, v);
    }
    logger->EmitLogRecord(std::move(record));
}

// --- Service startup ---
void OnStartup() {
    LogWithTrace(logs_api::Severity::kInfo, "service starting", {
        {"version", std::getenv("APP_VERSION") ? std::getenv("APP_VERSION") : "unknown"},
        {"environment", std::getenv("DEPLOYMENT_ENV") ? std::getenv("DEPLOYMENT_ENV") : "unknown"},
    });
}

// --- Request lifecycle ---
void OnRequestReceived(std::string_view method, std::string_view path) {
    LogWithTrace(logs_api::Severity::kInfo, "request received", {
        {"http.method", std::string(method)},
        {"http.path", std::string(path)},
    });
}

void OnRequestCompleted(std::string_view method, std::string_view path, int status) {
    LogWithTrace(logs_api::Severity::kInfo, "request completed", {
        {"http.method", std::string(method)},
        {"http.path", std::string(path)},
        {"http.status_code", std::to_string(status)},
    });
}

// --- Graceful shutdown ---
void OnShutdown() {
    LogWithTrace(logs_api::Severity::kInfo, "service shutting down");
    // Shut down providers (flushes pending logs/spans)
    logs_api::Provider::GetLoggerProvider()
        ->ForceFlush(std::chrono::microseconds(5000000));
    trace_api::Provider::GetTracerProvider()
        ->ForceFlush(std::chrono::microseconds(5000000));
    LogWithTrace(logs_api::Severity::kInfo, "otel providers shut down");
}
```

> C++ OTel logs are **stable** (not experimental). The `SetTraceId`/`SetSpanId` calls on log records enable trace-log correlation in Tsuga.
```
