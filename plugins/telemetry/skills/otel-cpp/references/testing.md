# Telemetry Testing — C++

## In-Memory Exporter Setup

```cpp
#include "opentelemetry/sdk/trace/tracer_provider.h"
#include "opentelemetry/sdk/trace/simple_processor.h"
#include "opentelemetry/exporters/memory/in_memory_span_exporter.h"

namespace trace_sdk = opentelemetry::sdk::trace;
namespace memory_exporter = opentelemetry::exporter::memory;
namespace trace_api = opentelemetry::trace;

class TelemetryTestFixture {
public:
    std::shared_ptr<memory_exporter::InMemorySpanData> span_data;
    std::shared_ptr<trace_sdk::TracerProvider> tracer_provider;

    void SetUp() {
        auto exporter = std::unique_ptr<memory_exporter::InMemorySpanExporter>(
            new memory_exporter::InMemorySpanExporter());
        span_data = exporter->GetData();  // Returns shared_ptr<InMemorySpanData>

        auto processor = std::unique_ptr<trace_sdk::SpanProcessor>(
            new trace_sdk::SimpleSpanProcessor(std::move(exporter)));

        tracer_provider = std::make_shared<trace_sdk::TracerProvider>(std::move(processor));
        opentelemetry::trace::Provider::SetTracerProvider(tracer_provider);
    }

    std::vector<std::unique_ptr<opentelemetry::sdk::trace::SpanData>> GetFinishedSpans() {
        return span_data->GetSpans();
    }
};
```

## Span Assertions

```cpp
#include <gtest/gtest.h>
#include <regex>

class OrderServiceTest : public ::testing::Test, public TelemetryTestFixture {
    void SetUp() override { TelemetryTestFixture::SetUp(); }
};

TEST_F(OrderServiceTest, CreatesServerRootSpan) {
    CreateOrder({"widget", 2});

    auto spans = GetFinishedSpans();
    ASSERT_FALSE(spans.empty()) << "Expected at least one span";

    std::vector<opentelemetry::sdk::trace::SpanData*> root_spans;
    for (auto& span : spans) {
        if (!span->GetParentSpanId().IsValid()) {
            root_spans.push_back(span.get());
        }
    }

    ASSERT_EQ(root_spans.size(), 1u) << "Expected 1 root span";
    EXPECT_EQ(root_spans[0]->GetName(), "POST /orders");
    EXPECT_EQ(root_spans[0]->GetSpanKind(), opentelemetry::trace::SpanKind::kServer);
}

TEST_F(OrderServiceTest, NoOrphanClientSpans) {
    CreateOrder({"widget", 2});

    for (auto& span : GetFinishedSpans()) {
        if (span->GetSpanKind() == opentelemetry::trace::SpanKind::kClient ||
            span->GetSpanKind() == opentelemetry::trace::SpanKind::kProducer) {
            EXPECT_TRUE(span->GetParentSpanId().IsValid())
                << "CLIENT/PRODUCER span '" << span->GetName() << "' has no parent";
        }
    }
}

TEST_F(OrderServiceTest, SpanNamesAreTemplates) {
    CreateOrder({"widget", 2});

    std::regex uuid_pattern("[0-9a-f]{8}-[0-9a-f]{4}");
    std::regex numeric_id_pattern("/[0-9]+");

    for (auto& span : GetFinishedSpans()) {
        std::string name(span->GetName());
        EXPECT_FALSE(std::regex_search(name, uuid_pattern))
            << "Span '" << name << "' contains UUID — use template";
        EXPECT_FALSE(std::regex_search(name, numeric_id_pattern))
            << "Span '" << name << "' contains numeric ID — use template";
    }
}
```

## Notes for C++

- C++ has no auto-instrumentation — all spans are manual. Test coverage of your instrumentation code is especially important.
- The InMemorySpanExporter is in the core `opentelemetry-cpp` SDK (under `exporters/memory`).
- Consider using `opentelemetry-cpp` testing utilities from the SDK's own test infrastructure.
