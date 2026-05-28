# Logs — Rust OTel

> Last verified: 2026-03-23 | SDK: opentelemetry 0.31.0 / opentelemetry-appender-tracing 0.31.0

## How Logs Work in Rust OTel

In Rust, the `tracing` crate is both the span and log layer. Every `tracing::event!` (i.e., `info!`, `warn!`, `error!`, `debug!`) emitted inside an active span is automatically correlated with that span's trace context via `tracing-opentelemetry`.

There are two complementary paths:

| Path | What it does |
|------|-------------|
| `tracing_subscriber::fmt::layer().json()` | Emits structured JSON to stdout; Collector `filelog` receiver picks it up |
| `opentelemetry-appender-tracing` | Exports `tracing` events directly as OTel log records via OTLP |

Use both for full coverage: stdout JSON for log aggregation, OTLP for correlated log records in Tsuga.

## Cargo.toml

```toml
[dependencies]
opentelemetry-appender-tracing = { version = "0.31", features = ["logs"] }
opentelemetry_sdk = { version = "0.31", features = ["logs"] }
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter", "json"] }
tracing-log = "0.2"   # optional: bridges log:: crate records into tracing
```

## Configuring the Appender

```rust
use opentelemetry_appender_tracing::layer::OpenTelemetryTracingBridge;
use opentelemetry_sdk::logs::SdkLoggerProvider;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

// Build a LoggerProvider with an OTLP exporter
let log_exporter = opentelemetry_otlp::LogExporter::builder()
    .with_http()
    .build()?;

let logger_provider = SdkLoggerProvider::builder()
    .with_resource(resource.clone())
    .with_batch_exporter(log_exporter)
    .build();

// GOOD — register both OTel log layer and JSON stdout layer
let otel_log_layer = OpenTelemetryTracingBridge::new(&logger_provider);

tracing_subscriber::registry()
    .with(tracing_subscriber::EnvFilter::from_default_env())
    .with(tracing_opentelemetry::layer().with_tracer(tracer))  // trace export
    .with(otel_log_layer)                                       // log export via OTLP
    .with(tracing_subscriber::fmt::layer().json())              // JSON to stdout
    .init();
```

## Emitting Logs

```rust
use tracing::{debug, error, info, warn};

// GOOD — structured fields are exported as log record attributes
info!(user_id = 123, action = "login", "user authenticated");
warn!(threshold = 0.9, current = 0.95, "high memory usage");
error!(error = %err, request_id = %req_id, "request failed");
debug!(query = %sql, duration_ms = elapsed, "db query completed");
```

> Use `%value` for Display formatting and `?value` for Debug formatting in tracing macros.

## Bridging the `log` Crate

If your code or dependencies use the `log` crate (`log::info!`, `log::error!`, etc.), those records produce no output unless bridged:

```rust
// GOOD — call once at startup, before any log:: macros fire
// Requires: tracing-log = "0.2" in Cargo.toml
tracing_log::LogTracer::init()?;
// Now log::info!("msg") routes through tracing → OTel
```

```rust
// BAD — log:: macros produce no OTel output without LogTracer
log::info!("something happened");  // goes nowhere unless bridged
```

## Trace Correlation (Automatic)

`tracing-opentelemetry` handles correlation natively. Every `tracing` event emitted within an active span automatically carries that span's `trace_id` and `span_id`.

No extra code is needed beyond the subscriber registration shown above.

**What you get in JSON stdout:**

```json
{
  "timestamp": "2026-03-23T10:00:00.000Z",
  "level": "INFO",
  "fields": { "message": "user authenticated", "user_id": 123 },
  "target": "my_service::handlers",
  "span": { "name": "handle_request" },
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7"
}
```

**What you get in Tsuga log records:**
- `trace_id` and `span_id` fields present on each log record
- Log records linked to the corresponding trace in the Tsuga UI

## Verification

```bash
# Confirm logs arrive with trace correlation
tsuga logs search --query "context.service.name:<your-service> trace_id:*" --max-results 3

# If trace_id is present but spans are not linking
tsuga spans search --query "context.service.name:<your-service> traceId:<trace-id-from-log>"

# Confirm JSON logs appear in stdout (check container logs)
# kubectl logs <pod> | grep trace_id
```

If verification fails:
- `trace_id` absent from logs → `tsuga-debug-missing-trace-propagation`
- Zero log results in Tsuga → `tsuga-debug-no-data`
- Using `log::` macros → add `tracing_log::LogTracer::init()` at startup
