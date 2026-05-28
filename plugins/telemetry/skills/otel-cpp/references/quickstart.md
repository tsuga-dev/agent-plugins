# Quick Start — C++ OTel

> **Last verified:** 2026-03-23 | SDK: `opentelemetry-cpp` 1.26.0

> Run `g++ --version` — C++14 or later required for opentelemetry-cpp 1.26.0. If compiler only supports C++11, stop and report to the user.

## Build Setup

> **Upgrading from 1.16.x?** Review the CHANGELOG between 1.16.1 and 1.26.0. Config-related APIs changed (file/declarative configuration was stabilized across this range). Consult the C++ API reference (https://opentelemetry.io/docs/languages/cpp/api/) for current factory patterns before migrating.

### Option A — vcpkg (recommended for CMake-first projects)

Install the package with the features you need:

```bash
# HTTP exporter only (default — port 4318)
vcpkg install "opentelemetry-cpp[otlp-http]"

# Add gRPC exporter support
vcpkg install "opentelemetry-cpp[otlp-http,otlp-grpc]"
```

Integrate with CMake (toolchain file approach):

```cmake
# In your CMakePresets.json or cmake invocation:
# -DCMAKE_TOOLCHAIN_FILE=/path/to/vcpkg/scripts/buildsystems/vcpkg.cmake
```

### Option B — Conan

```ini
# conanfile.txt
[requires]
opentelemetry-cpp/1.26.0

[options]
opentelemetry-cpp:with_otlp_http=True
opentelemetry-cpp:with_otlp_grpc=False   # set True to enable gRPC
```

```bash
conan install . --build=missing
```

### Option C — FetchContent (no package manager)

```cmake
include(FetchContent)
FetchContent_Declare(
    opentelemetry-cpp
    GIT_REPOSITORY https://github.com/open-telemetry/opentelemetry-cpp.git
    GIT_TAG        v1.26.0
)
set(WITH_OTLP_HTTP ON  CACHE BOOL "" FORCE)
set(WITH_OTLP_GRPC OFF CACHE BOOL "" FORCE)  # set ON for gRPC
FetchContent_MakeAvailable(opentelemetry-cpp)
```

## CMakeLists.txt — Required Targets

```cmake
find_package(opentelemetry-cpp CONFIG REQUIRED)

target_link_libraries(my-app PRIVATE
    opentelemetry-cpp::api
    opentelemetry-cpp::sdk
    opentelemetry-cpp::otlp_http_exporter          # HTTP/protobuf default (port 4318)
    # opentelemetry-cpp::otlp_grpc_exporter        # gRPC opt-in (port 4317)
    opentelemetry-cpp::metrics
    opentelemetry-cpp::logs
    opentelemetry-cpp::otlp_http_log_record_exporter
    opentelemetry-cpp::otlp_http_metric_exporter
)
```

> Exporter choice is made at link time. You cannot switch between HTTP and gRPC at runtime — change the CMake target and recompile.

## SDK Initialization

As of v1.15+, the C++ SDK auto-reads `OTEL_*` environment variables (e.g., `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_HEADERS`) in the exporter options constructors. You can still override values programmatically via the options structs or `std::getenv()` for custom logic.

```cpp
#include "opentelemetry/exporters/otlp/otlp_http_exporter_factory.h"
#include "opentelemetry/exporters/otlp/otlp_http_exporter_options.h"
#include "opentelemetry/exporters/otlp/otlp_http_metric_exporter_factory.h"
#include "opentelemetry/exporters/otlp/otlp_http_metric_exporter_options.h"
#include "opentelemetry/exporters/otlp/otlp_http_log_record_exporter_factory.h"
#include "opentelemetry/exporters/otlp/otlp_http_log_record_exporter_options.h"
#include "opentelemetry/sdk/trace/tracer_provider_factory.h"
#include "opentelemetry/sdk/trace/batch_span_processor_factory.h"
#include "opentelemetry/sdk/metrics/meter_provider_factory.h"
#include "opentelemetry/sdk/metrics/periodic_exporting_metric_reader_factory.h"
#include "opentelemetry/sdk/logs/logger_provider_factory.h"
#include "opentelemetry/sdk/logs/batch_log_record_processor_factory.h"
#include "opentelemetry/sdk/resource/resource.h"
#include "opentelemetry/trace/provider.h"
#include "opentelemetry/metrics/provider.h"
#include "opentelemetry/logs/provider.h"
#include "opentelemetry/context/propagation/global_propagator.h"
#include "opentelemetry/trace/propagation/http_trace_context.h"
#include <cstdlib>
#include <string>

namespace trace_sdk   = opentelemetry::sdk::trace;
namespace trace_api   = opentelemetry::trace;
namespace metrics_sdk = opentelemetry::sdk::metrics;
namespace metrics_api = opentelemetry::metrics;
namespace logs_sdk    = opentelemetry::sdk::logs;
namespace logs_api    = opentelemetry::logs;
namespace otlp        = opentelemetry::exporter::otlp;
namespace resource    = opentelemetry::sdk::resource;
namespace propagation = opentelemetry::context::propagation;

void InitTelemetry() {
    // OTEL_EXPORTER_OTLP_ENDPOINT and OTEL_EXPORTER_OTLP_HEADERS are auto-read
    // by the exporter options constructors. Service name and resource attributes
    // still benefit from explicit std::getenv() for use in Resource::Create().
    const char* svc_name_env = std::getenv("OTEL_SERVICE_NAME");
    std::string svc_name = svc_name_env ? svc_name_env : "my-service";

    const char* ep_env = std::getenv("OTEL_EXPORTER_OTLP_ENDPOINT");
    std::string base_url = ep_env ? ep_env : "http://localhost:4318";

    // Resource attributes are not auto-read from env; build from getenv() calls
    auto sdk_resource = resource::Resource::Create({
        {"service.name",               svc_name},
        {"service.version",            "1.0.0"},         // hardcode or read from env
        {"deployment.environment.name", "production"},   // or read from env
    });

    // --- Traces ---
    // Note: when using OTEL_EXPORTER_OTLP_ENDPOINT, the SDK auto-appends
    // /v1/traces (and /v1/metrics, /v1/logs) to the base URL. The manual
    // append below is for when you set the URL programmatically.
    otlp::OtlpHttpExporterOptions trace_opts;
    trace_opts.url = base_url + "/v1/traces";
    auto trace_exporter  = otlp::OtlpHttpExporterFactory::Create(trace_opts);
    auto trace_processor = trace_sdk::BatchSpanProcessorFactory::Create(
        std::move(trace_exporter), {}
    );
    auto trace_provider = trace_sdk::TracerProviderFactory::Create(
        std::move(trace_processor), sdk_resource
    );
    trace_api::Provider::SetTracerProvider(std::move(trace_provider));

    // --- Metrics ---
    otlp::OtlpHttpMetricExporterOptions metric_opts;
    metric_opts.url = base_url + "/v1/metrics";
    auto metric_exporter = otlp::OtlpHttpMetricExporterFactory::Create(metric_opts);

    metrics_sdk::PeriodicExportingMetricReaderOptions reader_opts;
    reader_opts.export_interval_millis = std::chrono::milliseconds(60000);  // 60s default
    auto metric_reader = metrics_sdk::PeriodicExportingMetricReaderFactory::Create(
        std::move(metric_exporter), reader_opts
    );
    auto meter_provider = metrics_sdk::MeterProviderFactory::Create(
        std::make_unique<metrics_sdk::ViewRegistry>(), sdk_resource
    );
    static_cast<metrics_sdk::MeterProvider&>(*meter_provider)
        .AddMetricReader(std::move(metric_reader));
    metrics_api::Provider::SetMeterProvider(std::move(meter_provider));

    // --- Logs ---
    otlp::OtlpHttpLogRecordExporterOptions log_opts;
    log_opts.url = base_url + "/v1/logs";
    auto log_exporter  = otlp::OtlpHttpLogRecordExporterFactory::Create(log_opts);
    auto log_processor = logs_sdk::BatchLogRecordProcessorFactory::Create(
        std::move(log_exporter), logs_sdk::BatchLogRecordProcessorOptions{}
    );
    auto log_provider = logs_sdk::LoggerProviderFactory::Create(
        std::move(log_processor), sdk_resource
    );
    logs_api::Provider::SetLoggerProvider(
        std::shared_ptr<logs_api::LoggerProvider>(log_provider.release())
    );

    // --- Propagator (required for distributed tracing) ---
    propagation::GlobalTextMapPropagator::SetGlobalPropagator(
        opentelemetry::nostd::shared_ptr<propagation::TextMapPropagator>(
            new opentelemetry::trace::propagation::HttpTraceContext()
        )
    );
}
```

## gRPC Exporter Variant

Swap the trace exporter section when targeting a gRPC Collector receiver (port 4317):

```cpp
#include "opentelemetry/exporters/otlp/otlp_grpc_exporter_factory.h"
#include "opentelemetry/exporters/otlp/otlp_grpc_exporter_options.h"

// gRPC endpoint — the SDK default is http://localhost:4317.
// The SDK strips the scheme internally when creating the gRPC channel,
// so both "http://localhost:4317" and "localhost:4317" work.
otlp::OtlpGrpcExporterOptions grpc_opts;
grpc_opts.endpoint = "http://localhost:4317";
grpc_opts.use_ssl_credentials = false;      // true for Tsuga / production TLS

auto trace_exporter = otlp::OtlpGrpcExporterFactory::Create(grpc_opts);
```

## Shutdown Hook (Required)

`BatchSpanProcessor` buffers spans in a background thread. Without an explicit shutdown, in-flight spans are dropped when the process exits.

```cpp
void ShutdownTelemetry() {
    // Resetting providers flushes and joins the background export thread
    trace_api::Provider::SetTracerProvider(
        opentelemetry::nostd::shared_ptr<trace_api::TracerProvider>{}
    );
    metrics_api::Provider::SetMeterProvider(
        opentelemetry::nostd::shared_ptr<metrics_api::MeterProvider>{}
    );
    opentelemetry::logs::Provider::SetLoggerProvider(
        opentelemetry::nostd::shared_ptr<logs_api::LoggerProvider>{}
    );
}

int main() {
    InitTelemetry();
    // ... application logic ...
    ShutdownTelemetry();   // MUST be called before return
    return 0;
}
```

For signal handling (SIGTERM, SIGINT), set a flag in the handler and call `ShutdownTelemetry()` from `main()` after the main loop exits — do not call it directly from a signal handler.

## Span Lifecycle — Two-Object Pattern

```cpp
// CORRECT — span + scope, End() in both try and catch
auto tracer = trace_api::Provider::GetTracerProvider()->GetTracer("my-app", "1.0.0");
auto span   = tracer->StartSpan("process order");
auto scope  = tracer->WithActiveSpan(span);   // makes span active in current thread

try {
    doWork();
    span->End();
} catch (const std::exception& e) {
    span->AddEvent("exception", {{"exception.type", typeid(e).name()},
                                  {"exception.message", e.what()}});
    span->SetStatus(trace_api::StatusCode::kError, e.what());
    span->End();   // MUST also End in catch
    throw;
}

// WRONG — End() only in try; exception skips it
auto span  = tracer->StartSpan("process order");
auto scope = tracer->WithActiveSpan(span);
doWork();
span->End();   // not reached if doWork() throws
```

> `scope` controls which span is "active" in context. Destroying `scope` deactivates the span from context but does NOT end it. Both objects must be managed.

## Required Environment Variables

```bash
# Minimum required — see references/resource-attributes.md to resolve the correct service name
OTEL_SERVICE_NAME=my-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318   # HTTP/protobuf default

# Recommended
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production,service.version=1.4.2
# Note: OTEL_EXPORTER_OTLP_ENDPOINT and OTEL_EXPORTER_OTLP_HEADERS are auto-read
# by exporter options constructors. OTEL_RESOURCE_ATTRIBUTES must still be parsed
# manually for use in Resource::Create().
```

## Post-Deploy Verification

```bash
# Confirm traces arrive
tsuga spans search --query "context.service.name:my-service" --max-results 5

# Confirm logs with trace correlation
tsuga logs search --query "context.service.name:my-service trace_id:*" --max-results 3

# Confirm metrics
tsuga metrics list --filter "service.name=my-service"
```

If no data: `tsuga-debug-no-data` skill.
If traces don't link across services: `tsuga-debug-missing-trace-propagation` skill.
