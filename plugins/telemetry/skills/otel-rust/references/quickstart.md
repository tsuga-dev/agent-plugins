# Quick Start — Rust OTel

> Last verified: 2026-03-23 | SDK: opentelemetry 0.31.0 / opentelemetry-otlp 0.31.1 / opentelemetry-sdk 0.31.0 / tracing-opentelemetry 0.32.1

> Run `rustc --version` — Rust 1.75.0+ (MSRV) required for opentelemetry 0.31.x. If below 1.75, use opentelemetry 0.30.x.

> **Beta stability warning:** The `opentelemetry` crate is pre-1.0. APIs can break between minor versions. Pin minor versions in `Cargo.toml` and review changelogs before upgrading. **Upgrading from 0.27.x?** The 0.28–0.31 range contains breaking API changes in builder patterns and exporter construction. Review the [official CHANGELOG](https://github.com/open-telemetry/opentelemetry-rust/blob/main/opentelemetry/CHANGELOG.md) before upgrading.

## Cargo.toml Setup

```toml
[dependencies]
# Core OTel API and SDK
opentelemetry = "0.31"
opentelemetry_sdk = { version = "0.31", features = ["logs"] }

# OTLP exporter — choose ONE protocol:
# HTTP/protobuf (default, recommended for most setups)
opentelemetry-otlp = { version = "0.31", features = ["http-proto", "reqwest-blocking-client"] }
# gRPC via tonic (opt-in)
# opentelemetry-otlp = { version = "0.31", features = ["grpc-tonic"] }

# OTel log appender for tracing bridge
opentelemetry-appender-tracing = { version = "0.31", features = ["logs"] }

# tracing ecosystem
tracing = "0.1"
tracing-opentelemetry = "0.32.1"
tracing-subscriber = { version = "0.3", features = ["env-filter", "json"] }
tracing-log = "0.2"      # bridges log:: crate records into tracing

# Async runtime
tokio = { version = "1", features = ["full"] }

# HTTP propagation helpers (needed for Axum / reqwest inject/extract)
opentelemetry-http = "0.31"
```

> **Feature flag rule:** `http-proto` → uses HTTP/protobuf on port 4318. `grpc-tonic` → uses gRPC on port 4317. This is a **compile-time** choice — `OTEL_EXPORTER_OTLP_PROTOCOL` env var is NOT honored at runtime in Rust.

> **Why `reqwest-blocking-client`?** The OTel `BatchSpanProcessor` runs exports on its own background thread, so a blocking HTTP call there does not block the tokio event loop. `reqwest-blocking-client` auto-wires an HTTP client so `.with_http().build()` just works. The async alternative (`reqwest-client`) requires an explicit `.with_http_client(reqwest::Client::new())` call — omitting it causes a runtime error: `no http client specified`. Use `reqwest-blocking-client` as the default; use `reqwest-client` only if you need custom async reqwest configuration (TLS, proxies, connection pooling).

> **Runtime note:** As of 0.28, `BatchSpanProcessor` and `PeriodicReader` spawn their own background threads and no longer require the `rt-tokio` feature. `grpc-tonic` requires a running Tokio runtime; `reqwest-blocking-client` (the HTTP default) does not.

## SDK Initialization

```rust
use opentelemetry::global;
use opentelemetry_sdk::{
    metrics::{PeriodicReader, SdkMeterProvider},
    propagation::TraceContextPropagator,
    trace::SdkTracerProvider,
    Resource,
};
use opentelemetry_appender_tracing::layer::OpenTelemetryTracingBridge;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

/// Initialize OTel SDK. Returns `SdkTracerProvider` — caller MUST keep alive until shutdown.
pub fn init_telemetry() -> Result<SdkTracerProvider, Box<dyn std::error::Error>> {
    // Set W3C TraceContext propagator (traceparent / tracestate headers)
    global::set_text_map_propagator(TraceContextPropagator::new());

    // Resource — reads OTEL_SERVICE_NAME and OTEL_RESOURCE_ATTRIBUTES automatically
    // Do NOT hardcode service.name here; use OTEL_SERVICE_NAME env var instead.
    let resource = Resource::builder()
        .build();

    // --- TracerProvider ---
    // Reads OTEL_EXPORTER_OTLP_ENDPOINT (default: http://localhost:4318)
    let span_exporter = opentelemetry_otlp::SpanExporter::builder()
        .with_http()
        .build()?;

    let tracer_provider = SdkTracerProvider::builder()
        .with_resource(resource.clone())
        .with_batch_exporter(span_exporter)
        .build();
    global::set_tracer_provider(tracer_provider.clone());

    // --- MeterProvider ---
    let metric_exporter = opentelemetry_otlp::MetricExporter::builder()
        .with_http()
        .build()?;
    let metric_reader = PeriodicReader::builder(metric_exporter)
        .build();
    let meter_provider = SdkMeterProvider::builder()
        .with_reader(metric_reader)
        .with_resource(resource.clone())
        .build();
    global::set_meter_provider(meter_provider);

    // --- LoggerProvider ---
    let log_exporter = opentelemetry_otlp::LogExporter::builder()
        .with_http()
        .build()?;
    let logger_provider = opentelemetry_sdk::logs::SdkLoggerProvider::builder()
        .with_resource(resource.clone())
        .with_batch_exporter(log_exporter)
        .build();

    // --- tracing subscriber ---
    let tracer = tracer_provider.tracer("my-service");
    let otel_trace_layer = tracing_opentelemetry::layer().with_tracer(tracer);
    let otel_log_layer = OpenTelemetryTracingBridge::new(&logger_provider);

    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::from_default_env()) // reads RUST_LOG
        .with(otel_trace_layer)
        .with(otel_log_layer)
        .with(tracing_subscriber::fmt::layer().json())           // JSON to stdout
        .init();

    // Bridge log:: crate records into tracing (optional, needed if deps use log::)
    // tracing_log::LogTracer::init()?;

    Ok(tracer_provider)
}

/// Flush and shut down all OTel providers. Call before process exits.
pub async fn shutdown_telemetry(tracer_provider: SdkTracerProvider) {
    // Flush and shut down tracer provider
    if let Err(e) = tracer_provider.shutdown() {
        eprintln!("tracer provider shutdown error: {e}");
    }
    // Flush meter provider
    global::shutdown_tracer_provider();
}
```

> **Why return `SdkTracerProvider`?** If the provider is dropped at the end of `init_telemetry`, the `BatchSpanProcessor` shuts down and no spans are exported. The caller must hold it until process exit.

## main.rs Wiring

```rust
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let tracer_provider = init_telemetry()?;

    // ... run your application ...
    run_server().await?;

    // Always call shutdown before exit — flushes in-flight spans and metrics
    shutdown_telemetry(tracer_provider).await;
    Ok(())
}
```

## gRPC Opt-In (tonic)

```toml
# Cargo.toml — swap http-proto for grpc-tonic
opentelemetry-otlp = { version = "0.31", features = ["grpc-tonic"] }
tonic = "0.12"
```

```rust
// Use .with_tonic() instead of .with_http() in all exporter builders
let span_exporter = opentelemetry_otlp::SpanExporter::builder()
    .with_tonic()
    .build()?;
// Reads OTEL_EXPORTER_OTLP_ENDPOINT (default: http://localhost:4317 for gRPC)
```

> Set `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317` when using `grpc-tonic`.

## Environment Variables

```bash
# Minimum required — see references/resource-attributes.md to resolve the correct service name
OTEL_SERVICE_NAME=my-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318   # HTTP/protobuf default

# Recommended
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production,service.version=1.4.2

# Log level (controls which tracing spans/events are emitted)
RUST_LOG=info

# gRPC opt-in (requires grpc-tonic Cargo feature)
# OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
```

> `OTEL_EXPORTER_OTLP_PROTOCOL` is NOT read at runtime in Rust. Protocol is selected at compile time by Cargo feature (`http-proto` vs `grpc-tonic`).

## Post-Deploy Verification

```bash
# Confirm traces arrive
tsuga spans search --query "context.service.name:my-service" --max-results 5

# Confirm logs with trace correlation
tsuga logs search --query "context.service.name:my-service trace_id:*" --max-results 3

# Confirm metrics
tsuga metrics list --filter "service.name=my-service"
```

If no data appears: `tsuga-debug-no-data` skill.
If traces don't link across services: `tsuga-debug-missing-trace-propagation` skill.
