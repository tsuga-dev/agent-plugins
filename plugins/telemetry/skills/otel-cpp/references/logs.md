# Logs — C++ OTel

> **Last verified:** 2026-03-23 | SDK: `opentelemetry-cpp` 1.26.0
>
> The C++ OTel Logs SDK is **stable** as of 1.16.1.

## Path Selection

| Scenario | Path |
|----------|------|
| Already using spdlog; want trace correlation in log output | **Path A** — spdlog custom sink bridging to OTel Logs SDK |
| Want minimal OTel log records without spdlog | **Path B** — direct OTel Logger API |
| Need trace correlation in existing spdlog output only (no OTel log pipeline) | **Path C** — manual trace context injection into spdlog messages |

## Path A — spdlog Bridge to OTel Logs SDK (Recommended)

Build a custom spdlog sink that forwards log records to the OTel `Logger` API. The sink reads the active span context and injects `trace_id` and `span_id` automatically.

```cpp
#include <spdlog/sinks/base_sink.h>
#include "opentelemetry/logs/provider.h"
#include "opentelemetry/trace/provider.h"
#include "opentelemetry/context/runtime_context.h"

namespace logs_api  = opentelemetry::logs;
namespace trace_api = opentelemetry::trace;

class OtelSpdlogSink : public spdlog::sinks::base_sink<std::mutex> {
    std::shared_ptr<logs_api::Logger> logger_;

public:
    explicit OtelSpdlogSink(const std::string& logger_name) {
        // GetLogger(logger_name, library_name, library_version, ...)
        logger_ = logs_api::Provider::GetLoggerProvider()
                      ->GetLogger(logger_name);
    }

protected:
    void sink_it_(const spdlog::details::log_msg& msg) override {
        // Map spdlog level to OTel severity
        auto severity = ToOtelSeverity(msg.level);

        auto log_record = logger_->CreateLogRecord();
        if (!log_record) return;

        log_record->SetSeverity(severity);
        log_record->SetBody(std::string(msg.payload.begin(), msg.payload.end()));

        // Inject active span context for trace-log correlation
        auto span_ctx = trace_api::GetSpan(
            opentelemetry::context::RuntimeContext::GetCurrent()
        )->GetContext();

        if (span_ctx.IsValid()) {
            log_record->SetTraceId(span_ctx.trace_id());
            log_record->SetSpanId(span_ctx.span_id());
            log_record->SetTraceFlags(span_ctx.trace_flags());
        }

        logger_->EmitLogRecord(std::move(log_record));
    }

    void flush_() override {}

    static logs_api::Severity ToOtelSeverity(spdlog::level::level_enum level) {
        switch (level) {
            case spdlog::level::trace: return logs_api::Severity::kTrace;
            case spdlog::level::debug: return logs_api::Severity::kDebug;
            case spdlog::level::info:  return logs_api::Severity::kInfo;
            case spdlog::level::warn:  return logs_api::Severity::kWarn;
            case spdlog::level::err:   return logs_api::Severity::kError;
            case spdlog::level::critical: return logs_api::Severity::kFatal;
            default: return logs_api::Severity::kInfo;
        }
    }
};
```

Register the sink at init time (after `InitTelemetry()` has set up the LoggerProvider):

```cpp
// After InitTelemetry():
auto otel_sink = std::make_shared<OtelSpdlogSink>("my-service");
auto logger = std::make_shared<spdlog::logger>("main", otel_sink);
spdlog::set_default_logger(logger);
spdlog::set_level(spdlog::level::info);
```

## Path B — Direct OTel Logger API

Use when you do not use spdlog and want to write log records directly into the OTel pipeline.

```cpp
#include "opentelemetry/logs/provider.h"
#include "opentelemetry/trace/provider.h"
#include "opentelemetry/context/runtime_context.h"

namespace logs_api  = opentelemetry::logs;
namespace trace_api = opentelemetry::trace;

// GetLogger(logger_name, library_name, library_version, ...)
// Second param is library_name, not version.
auto logger = logs_api::Provider::GetLoggerProvider()
                  ->GetLogger("my-service");

auto log_record = logger->CreateLogRecord();
if (log_record) {
    log_record->SetSeverity(logs_api::Severity::kInfo);
    log_record->SetBody("order placed");
    log_record->SetAttribute("order.id", order_id);

    // Inject trace context
    auto span_ctx = trace_api::GetSpan(
        opentelemetry::context::RuntimeContext::GetCurrent()
    )->GetContext();
    if (span_ctx.IsValid()) {
        log_record->SetTraceId(span_ctx.trace_id());
        log_record->SetSpanId(span_ctx.span_id());
        log_record->SetTraceFlags(span_ctx.trace_flags());
    }

    logger->EmitLogRecord(std::move(log_record));
}
```

## Path C — Manual Trace Context Injection into spdlog (No OTel Log Pipeline)

Use when you only need trace correlation in log output (stdout/file) and do not need OTel log records flowing to the Collector.

```cpp
#include "opentelemetry/context/runtime_context.h"
#include "opentelemetry/trace/span.h"
#include <spdlog/spdlog.h>
#include <array>

void LogWithTrace(spdlog::level::level_enum level, const std::string& message) {
    auto span_ctx = opentelemetry::trace::GetSpan(
        opentelemetry::context::RuntimeContext::GetCurrent()
    )->GetContext();

    if (span_ctx.IsValid()) {
        std::array<char, 33> trace_id_hex{};
        std::array<char, 17> span_id_hex{};
        span_ctx.trace_id().ToLowerBase16(trace_id_hex);
        span_ctx.span_id().ToLowerBase16(span_id_hex);
        trace_id_hex[32] = '\0';
        span_id_hex[16]  = '\0';
        spdlog::log(level,
            R"({{"trace_id":"{}","span_id":"{}","message":"{}"}})",
            trace_id_hex.data(), span_id_hex.data(), message);
    } else {
        spdlog::log(level, R"({{"message":"{}"}})", message);
    }
}

#define LOG_INFO(msg)  LogWithTrace(spdlog::level::info, msg)
#define LOG_ERROR(msg) LogWithTrace(spdlog::level::err, msg)
```

> **Thread safety note:** `RuntimeContext::GetCurrent()` reads the thread-local context. This is safe when called from the same thread that owns the active span. If you log from a different thread (e.g., a thread pool task), you must propagate the `Context` object explicitly to that thread.

## Trace Correlation in Log Records

For trace correlation to work in Tsuga, log records must include `trace_id` and `span_id` fields. Path A (spdlog sink) and Path B (direct OTel Logger) both inject these automatically from the active span context. Path C injects them into the formatted message string.

Required fields for Tsuga correlation:

| Field | Source |
|-------|--------|
| `trace_id` | `span_ctx.trace_id()` converted to hex |
| `span_id` | `span_ctx.span_id()` converted to hex |

## Verification

```bash
# Confirm logs arrive with trace correlation
tsuga logs search --query "context.service.name:my-service trace_id:*" --max-results 3

# If trace_id is present but spans are not linking
tsuga spans search --query "context.service.name:my-service traceId:<trace-id-from-log>"
```

If verification fails:
- `trace_id` absent from logs → `tsuga-debug-missing-trace-propagation`
- Zero log results → `tsuga-debug-no-data`
