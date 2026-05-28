# Local Verification — C++

## Overview

Before routing telemetry to a production collector, verify C++ instrumentation by printing spans to stdout using `OStreamSpanExporter`. Pair it with `SimpleSpanProcessor` so each span is exported synchronously when it ends. For any process that terminates after completing its work, call `provider->Shutdown()` before exiting to ensure all spans have been written and SDK resources are released cleanly.

> ⚠️ **JSON vs text output:** `OStreamSpanExporter` produces human-readable text blocks to `std::cout`.
> It does NOT produce JSON. For parseable JSON output (e.g., in benchmarks or integration tests),
> use `OtlpFileExporter` instead — see section below.

## OtlpFileExporter (JSONL — camelCase OTLP JSON)

Use `OtlpFileExporter` when you need parseable JSON output — for example, in benchmarks, integration tests, or any scenario where the output will be read by a program.

**CMakeLists.txt dependency:**

```cmake
find_package(opentelemetry-cpp REQUIRED)
target_link_libraries(my_target
    opentelemetry-cpp::trace
    opentelemetry-cpp::otlp_file_exporter
)
```

**Required headers:**

```cpp
#include "opentelemetry/exporters/otlp/otlp_file_exporter_factory.h"
#include "opentelemetry/exporters/otlp/otlp_file_exporter_options.h"

namespace otlp_exp = opentelemetry::exporter::otlp;
```

**Tracer provider setup:**

```cpp
void InitTracer() {
    otlp_exp::OtlpFileExporterOptions opts;
    opts.file_pattern = "/tmp/spans-%N.jsonl"; // %N increments per file rotation

    auto exporter = otlp_exp::OtlpFileExporterFactory::Create(opts);
    auto processor = trace_sdk::SimpleSpanProcessorFactory::Create(std::move(exporter));

    auto resource = opentelemetry::sdk::resource::Resource::Create({
        {"service.name", "my-service"},
    });

    auto provider = trace_sdk::TracerProviderFactory::Create(
        std::move(processor), resource);

    trace_api::Provider::SetTracerProvider(
        std::shared_ptr<trace_api::TracerProvider>(std::move(provider)));
}
```

**Output format:** JSONL — each line is one complete OTLP JSON object with **camelCase keys** per the
[OTLP spec](https://opentelemetry.io/docs/specs/otlp/#json-protobuf-encoding). Example of one line:

```json
{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"my-service"}}]},"scopeSpans":[{"spans":[{"traceId":"...","spanId":"...","name":"http.request","kind":2,...}]}]}]}
```

Note: `OtlpFileExporter` is available since opentelemetry-cpp v1.15.0.

## OStreamSpanExporter (human-readable text — not JSON)

Include the header and link against the OStream exporter:

```cpp
#include "opentelemetry/exporters/ostream/span_exporter.h"
#include "opentelemetry/exporters/ostream/span_exporter_factory.h"
#include "opentelemetry/sdk/trace/processor.h"
#include "opentelemetry/sdk/trace/simple_processor_factory.h"
#include "opentelemetry/sdk/trace/tracer_provider_factory.h"
#include "opentelemetry/trace/provider.h"

namespace trace_api = opentelemetry::trace;
namespace trace_sdk = opentelemetry::sdk::trace;
namespace ostream_exp = opentelemetry::exporter::trace;
```

**CMakeLists.txt dependency:**

```cmake
find_package(opentelemetry-cpp REQUIRED)
target_link_libraries(my_target
    opentelemetry-cpp::trace
    opentelemetry-cpp::ostream_span_exporter
)
```

**Tracer provider setup:**

```cpp
void InitTracer() {
    auto exporter = ostream_exp::OStreamSpanExporterFactory::Create();
    auto processor = trace_sdk::SimpleSpanProcessorFactory::Create(std::move(exporter));

    auto resource = opentelemetry::sdk::resource::Resource::Create({
        {"service.name", "my-service"},
    });

    auto provider = trace_sdk::TracerProviderFactory::Create(
        std::move(processor), resource);

    trace_api::Provider::SetTracerProvider(
        std::shared_ptr<trace_api::TracerProvider>(std::move(provider)));
}
```

Each finished span is printed to `std::cout` as a structured text block with trace ID, span ID, parent span ID, name, kind, attributes, and timing.

⚠️ This output is NOT JSON. Do not attempt to parse it with a JSON parser. For JSON output, use `OtlpFileExporter`.

## SimpleSpanProcessor vs BatchSpanProcessor

| | `SimpleSpanProcessor` | `BatchSpanProcessor` |
|---|---|---|
| Export timing | Synchronous, on span end | Async, background thread |
| Local testing | Preferred — spans appear on `span->End()` | Requires `Shutdown()` to flush; may miss spans |
| Production | Not recommended for high-throughput | Correct choice |

Use `SimpleSpanProcessorFactory::Create` for all local development. `BatchSpanProcessorFactory::Create` is appropriate for production OTLP export where throughput matters.

## Parent-Child Span Relationship in stdout Output

Seeing the parent span ID in the output confirms that child spans are correctly nested under their parent.

```cpp
#include "opentelemetry/trace/scope.h"

void ProcessRequest() {
    auto tracer = trace_api::Provider::GetTracerProvider()
        ->GetTracer("my-service");

    // Root span
    auto root_span = tracer->StartSpan("http.request");
    auto root_scope = tracer->WithActiveSpan(root_span);

    {
        // Child span — parentSpanId in output must match root_span's spanId
        auto child_span = tracer->StartSpan("db.query");
        auto child_scope = tracer->WithActiveSpan(child_span);

        child_span->SetAttribute("db.statement", "SELECT * FROM orders");
        ExecuteQuery();

        child_span->End();
    }

    root_span->SetAttribute("http.status_code", 200);
    root_span->End();
}
```

In the stdout output, `child_span` will show a `parentSpanId` equal to `root_span`'s `spanId`. If `parentSpanId` is absent or zero, context propagation through `WithActiveSpan` is not working correctly.

## Short-Lived Processes

Call `provider->Shutdown()` before the process exits. The `SimpleSpanProcessor` is synchronous, so all spans have already been exported by the time `End()` returns — but `Shutdown()` also closes the exporter and releases background resources.

```cpp
#include <csignal>

namespace {
    std::shared_ptr<trace_api::TracerProvider> g_provider;
}

void SignalHandler(int) {
    if (g_provider) {
        auto* sdk_provider =
            static_cast<trace_sdk::TracerProvider*>(g_provider.get());
        sdk_provider->Shutdown();
    }
    std::exit(0);
}

int main() {
    InitTracer();
    g_provider = trace_api::Provider::GetTracerProvider();

    std::signal(SIGTERM, SignalHandler);
    std::signal(SIGINT, SignalHandler);

    ProcessRequest();

    // Explicit shutdown for normal exit
    auto* sdk_provider =
        static_cast<trace_sdk::TracerProvider*>(g_provider.get());
    sdk_provider->Shutdown();

    return 0;
}
```

## OTEL_TRACES_EXPORTER Environment Variable

The C++ OTel SDK does not support `OTEL_TRACES_EXPORTER=console` natively. Configure the `OStreamSpanExporter` explicitly in code. To switch between local and production exporters based on environment:

```cpp
#include <cstdlib>

void InitTracer() {
    const char* exporter_env = std::getenv("OTEL_TRACES_EXPORTER");
    std::string exporter_type = exporter_env ? exporter_env : "otlp";

    std::unique_ptr<trace_sdk::SpanExporter> exporter;

    if (exporter_type == "console" || exporter_type == "ostream") {
        exporter = ostream_exp::OStreamSpanExporterFactory::Create();
    } else {
        // Configure OTLP exporter for production
        exporter = CreateOtlpExporter(); // your OTLP setup
    }

    auto processor = trace_sdk::SimpleSpanProcessorFactory::Create(
        std::move(exporter));
    // ... rest of provider setup
}
```

## Local Collector with Debug Exporter

Run `otelcol-contrib` locally to validate the full OTLP export path. The `debug` exporter prints every received span and metric with full attribute detail.

```yaml
# otelcol-config.yaml — local debug collector
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

exporters:
  debug:
    verbosity: detailed

service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [debug]
    metrics:
      receivers: [otlp]
      exporters: [debug]
```

Link against the OTLP exporter and point it at the local collector:

```cmake
target_link_libraries(my_target
    opentelemetry-cpp::otlp_grpc_exporter
)
```

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
OTEL_SERVICE_NAME=my-service \
./my_target
```
