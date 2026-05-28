# Endpoint, Protocol, and Troubleshooting — C++

> **Last verified:** 2026-03-23 | SDK: `opentelemetry-cpp` 1.26.0

## OTLP Protocol Reference

| Protocol | Port | Path auto-appended by SDK? | CMake target |
|----------|------|---------------------------|--------------|
| OTLP/HTTP | 4318 | Yes (`/v1/traces`, `/v1/metrics`, `/v1/logs`) | `opentelemetry-cpp::otlp_http_exporter` |
| OTLP/gRPC | 4317 | No | `opentelemetry-cpp::otlp_grpc_exporter` |

**Default for new services:** `OtlpHttpExporter` on port 4318 (HTTP/protobuf). This matches the OTel spec default. gRPC is opt-in.

Protocol defaults by path:

| Path | Default protocol | Default port | Notes |
|------|-----------------|--------------|-------|
| `OtlpHttpExporterFactory` | `http/protobuf` | 4318 | HTTP exporters auto-append `/v1/traces` etc. |
| `OtlpGrpcExporterFactory` | `grpc` | 4317 | Default: `http://localhost:4317`; SDK strips scheme internally |

When using `OTEL_EXPORTER_OTLP_ENDPOINT` (the base endpoint env var), the SDK auto-appends the signal path (`/v1/traces`, `/v1/metrics`, `/v1/logs`) — do not include `/v1/traces` in that env var. When setting the URL programmatically via `OtlpHttpExporterOptions.url`, you must set the full URL including the path (e.g., `http://localhost:4318/v1/traces`).

## Tsuga Endpoint Configuration

**HTTP/protobuf (recommended):**

```cpp
#include "opentelemetry/exporters/otlp/otlp_http_exporter_factory.h"
#include "opentelemetry/exporters/otlp/otlp_http_exporter_options.h"

namespace otlp = opentelemetry::exporter::otlp;

otlp::OtlpHttpExporterOptions http_opts;
http_opts.url = "https://ingest.<region>.tsuga.cloud:443/v1/traces";
http_opts.http_headers.insert({"tsuga-ingestion-key",
    std::getenv("TSUGA_INGESTION_KEY") ? std::getenv("TSUGA_INGESTION_KEY") : ""});

auto trace_exporter = otlp::OtlpHttpExporterFactory::Create(http_opts);
```

**gRPC:**

```cpp
#include "opentelemetry/exporters/otlp/otlp_grpc_exporter_factory.h"
#include "opentelemetry/exporters/otlp/otlp_grpc_exporter_options.h"

otlp::OtlpGrpcExporterOptions grpc_opts;
grpc_opts.endpoint           = "ingest.<region>.tsuga.cloud:443";
grpc_opts.use_ssl_credentials = true;
// Leave ssl_credentials_cacert_as_string empty to use system CA store
grpc_opts.metadata.insert({"tsuga-ingestion-key",
    std::getenv("TSUGA_INGESTION_KEY") ? std::getenv("TSUGA_INGESTION_KEY") : ""});

auto trace_exporter = otlp::OtlpGrpcExporterFactory::Create(grpc_opts);
```

**Via environment variables (read manually in init code):**

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://ingest.<region>.tsuga.cloud:443
OTEL_EXPORTER_OTLP_HEADERS=tsuga-ingestion-key=<your-key>
OTEL_SERVICE_NAME=my-service
```

> As of v1.15+, the C++ SDK auto-reads `OTEL_*` environment variables (e.g., `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_HEADERS`) in the exporter options constructors. You can still override values programmatically via the options structs or `std::getenv()` for custom logic.

## Common Issues

### No spans arriving

1. **`ShutdownTelemetry()` not called:** The `BatchSpanProcessor` buffers spans in a background thread. Without calling `SetTracerProvider({})`, the buffer may not flush before process exit.
2. **Binary not linked to exporter:** If `otlp_http_exporter` or `otlp_grpc_exporter` is not in CMakeLists.txt `target_link_libraries`, spans go nowhere.
3. **gRPC endpoint format:** The SDK default is `http://localhost:4317`. The SDK strips the scheme internally when creating the gRPC channel, so both `http://localhost:4317` and `localhost:4317` work.
4. **Missing resource attributes:** Without `service.name`, spans arrive with no service identity in Tsuga.
   > To determine the correct service name, see `references/resource-attributes.md` → **Resolve resource attribute values**.
5. **Global propagator not set:** Inbound `Extract()` calls are no-ops and spans won't have parent context — call `GlobalTextMapPropagator::SetGlobalPropagator(...)` in `InitTelemetry()`.

### Link errors at build time

```
undefined reference to `opentelemetry::exporter::otlp::OtlpHttpExporterFactory::Create`
```

Add to CMakeLists.txt:

```cmake
target_link_libraries(my-app PRIVATE opentelemetry-cpp::otlp_http_exporter)
```

For gRPC:

```cmake
target_link_libraries(my-app PRIVATE opentelemetry-cpp::otlp_grpc_exporter)
```

Also ensure vcpkg/Conan has the required feature enabled:

```bash
# vcpkg
vcpkg install "opentelemetry-cpp[otlp-http]"
vcpkg install "opentelemetry-cpp[otlp-grpc]"    # gRPC only
```

### gRPC TLS for Tsuga

```cpp
otlp::OtlpGrpcExporterOptions opts;
opts.endpoint            = "ingest.<region>.tsuga.cloud:443";
opts.use_ssl_credentials = true;
// Leave ssl_credentials_cacert_as_string empty to use system CA store
// Or provide the CA cert content as a string for custom CA
```

For local development without TLS:

```cpp
opts.endpoint            = "localhost:4317";
opts.use_ssl_credentials = false;   // plaintext gRPC
```

### `BatchSpanProcessor` not exporting

The default export interval is 5 seconds. Verify options:

```cpp
trace_sdk::BatchSpanProcessorOptions bsp_opts;
bsp_opts.schedule_delay_millis  = std::chrono::milliseconds(5000);
bsp_opts.max_export_batch_size  = 512;
bsp_opts.max_queue_size         = 2048;

auto batch_processor = trace_sdk::BatchSpanProcessorFactory::Create(
    std::move(exporter), bsp_opts
);
```

### Span attributes rejected or missing

OTel C++ attributes use `opentelemetry::common::AttributeValue` — a variant type. Use explicit casts:

```cpp
// WRONG — implicit int conversion may not produce int64_t on all platforms
span->SetAttribute("count", 42);

// CORRECT — explicit types
span->SetAttribute("count",    static_cast<int64_t>(42));
span->SetAttribute("ratio",    0.95);           // double — OK
span->SetAttribute("endpoint", "/api/orders");  // const char* → string_view — OK
```

### HTTP exporter: URL path handling

When setting `OtlpHttpExporterOptions.url` programmatically, include the full path:

```cpp
// CORRECT — programmatic URL must include the signal path
http_opts.url = base_url + "/v1/traces";   // e.g., "http://localhost:4318/v1/traces"
```

When using the `OTEL_EXPORTER_OTLP_ENDPOINT` env var (auto-read by the options constructor), the SDK appends `/v1/traces` automatically. Do not double-append the path in that case.

## Shutdown / Flush

The C++ SDK's `BatchSpanProcessor` runs a background thread. Flushing requires resetting the provider to an empty `shared_ptr`.

**Basic shutdown:**

```cpp
void ShutdownTelemetry() {
    opentelemetry::trace::Provider::SetTracerProvider(
        opentelemetry::nostd::shared_ptr<opentelemetry::trace::TracerProvider>{}
    );
    opentelemetry::metrics::Provider::SetMeterProvider(
        opentelemetry::nostd::shared_ptr<opentelemetry::metrics::MeterProvider>{}
    );
    opentelemetry::logs::Provider::SetLoggerProvider(
        opentelemetry::nostd::shared_ptr<opentelemetry::logs::LoggerProvider>{}
    );
}
```

**Signal handling:**

```cpp
#include <csignal>
#include <atomic>

std::atomic<bool> g_shutdown{false};

void SignalHandler(int /*signum*/) {
    g_shutdown = true;
}

int main() {
    InitTelemetry();
    std::signal(SIGTERM, SignalHandler);
    std::signal(SIGINT,  SignalHandler);

    while (!g_shutdown) {
        // main loop
    }

    ShutdownTelemetry();
    return 0;
}
```

**Common shutdown mistakes:**

- Calling `ShutdownTelemetry()` before all worker threads finish — active spans being written while provider is shut down cause race conditions
- Not calling `ShutdownTelemetry()` at all — last batch of spans (up to 5 seconds of data) silently dropped
- Using `SimpleSpanProcessorFactory` in production then wondering why performance degrades — Simple blocks on every export; Batch is async

## Resilience: Collector Unavailable

When the OTLP collector is unreachable, the C++ OTel SDK does **not** crash the service. Export errors are returned from the exporter's `Export()` method and handled by the `BatchSpanProcessor` (retries then drops oldest spans when queue fills). The application continues normally.

**Conditional setup (no-op when no endpoint configured):**

```cpp
void InitTracing(const std::string& endpoint) {
    if (endpoint.empty()) {
        // No collector — install a no-op provider; spans are created but not exported
        trace_api::Provider::SetTracerProvider(
            opentelemetry::nostd::shared_ptr<trace_api::TracerProvider>(
                new opentelemetry::trace::NoopTracerProvider()
            )
        );
        return;
    }

    otlp::OtlpHttpExporterOptions opts;
    opts.url = endpoint + "/v1/traces";
    auto exporter   = otlp::OtlpHttpExporterFactory::Create(opts);
    auto processor  = trace_sdk::BatchSpanProcessorFactory::Create(
        std::move(exporter), {}
    );
    auto provider   = trace_sdk::TracerProviderFactory::Create(std::move(processor));
    trace_api::Provider::SetTracerProvider(std::move(provider));
}
```

**Disable OTel:**

```bash
# Check in init code and skip provider setup
OTEL_SDK_DISABLED=true ./my-service
```

```cpp
// In InitTelemetry():
const char* disabled = std::getenv("OTEL_SDK_DISABLED");
if (disabled && std::string(disabled) == "true") {
    return;  // skip all provider setup
}
```

**Thread safety:** The `BatchSpanProcessor` is thread-safe. Export failures on the background export thread do not affect the main application threads.
