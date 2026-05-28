# Endpoint, Protocol, and Troubleshooting — Rust

> Last verified: 2026-03-23 | SDK: opentelemetry 0.31.0 / opentelemetry-otlp 0.31.0

## OTLP Protocol Reference

| Protocol | Port | Path auto-appended by SDK? | Cargo feature |
|----------|------|---------------------------|---------------|
| OTLP/gRPC | 4317 | No | `grpc-tonic` |
| OTLP/HTTP/protobuf | 4318 | Yes (`/v1/traces`, `/v1/metrics`, `/v1/logs`) | `http-proto` |
| OTLP/HTTP/JSON | 4318 | Yes | `http-json` |

> **Protocol is a compile-time choice in Rust.** Use the Cargo feature (`http-proto` vs `grpc-tonic`) to select the protocol — `OTEL_EXPORTER_OTLP_PROTOCOL` env var is NOT honored at runtime.

Protocol defaults differ by Cargo feature:

| Cargo feature | Default protocol | Default port | Builder method |
|---------------|-----------------|--------------|----------------|
| `http-proto` (recommended) | OTLP/HTTP/protobuf | 4318 | `.with_http()` |
| `grpc-tonic` | OTLP/gRPC | 4317 | `.with_tonic()` |

HTTP exporters auto-append the signal path — do not include `/v1/traces` in `OTEL_EXPORTER_OTLP_ENDPOINT`.

> **Tokio runtime required for transports:** Both `grpc-tonic` and `reqwest-client` transports require a running Tokio runtime. Ensure `MeterProvider` and exporter initialization happens within a `#[tokio::main]` or active Tokio context.

## Tsuga Endpoint Configuration

**HTTP/protobuf (recommended):**

```toml
[dependencies]
opentelemetry-otlp = { version = "0.31", features = ["http-proto", "reqwest-client"] }
```

```rust
use opentelemetry_otlp::{WithExportConfig, WithHttpConfig};

let otlp_exporter = opentelemetry_otlp::SpanExporter::builder()
    .with_http()
    .with_endpoint("https://ingest.<region>.tsuga.cloud:443")
    .with_headers(std::collections::HashMap::from([(
        "tsuga-ingestion-key".to_string(),
        std::env::var("TSUGA_INGESTION_KEY").expect("TSUGA_INGESTION_KEY not set"),
    )]))
    .build()?;
// SDK auto-appends /v1/traces to the endpoint
```

**gRPC/tonic:**

```toml
[dependencies]
opentelemetry-otlp = { version = "0.31", features = ["grpc-tonic"] }
tonic = "0.12"
```

```rust
use opentelemetry_otlp::WithExportConfig;
use tonic::metadata::MetadataValue;

let mut metadata = tonic::metadata::MetadataMap::new();
metadata.insert(
    "tsuga-ingestion-key",
    MetadataValue::try_from(
        std::env::var("TSUGA_INGESTION_KEY").expect("TSUGA_INGESTION_KEY not set")
    ).unwrap(),
);

let otlp_exporter = opentelemetry_otlp::SpanExporter::builder()
    .with_tonic()
    .with_endpoint("https://ingest.<region>.tsuga.cloud:443")
    .with_metadata(metadata)
    .build()?;
```

**Via environment variables (recommended):**

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://ingest.<region>.tsuga.cloud:443
OTEL_EXPORTER_OTLP_HEADERS=tsuga-ingestion-key=<your-key>
OTEL_SERVICE_NAME=my-service
RUST_LOG=info
```

> To determine the correct service name, see `references/resource-attributes.md` → **Resolve resource attribute values**.

## Common Issues

### No spans arriving

1. **Transport requires Tokio runtime:** `grpc-tonic` and `reqwest-client` transports require a running Tokio runtime. Ensure your exporter is created within a `#[tokio::main]` or active Tokio context.
2. **`SdkTracerProvider` dropped early:** If the provider is not returned from `init_telemetry`, it drops when the function returns, shutting down the batch exporter immediately.
3. **`global::set_tracer_provider` not called:** `tracing-opentelemetry` gets its tracer from the global provider. Without this call, spans are no-ops.
4. **`global::shutdown_tracer_provider()` not called on exit:** The last batch (up to 5 s of spans) is not flushed before the process exits.
5. **Port mismatch:** `grpc-tonic` feature requires port 4317; `http-proto` requires port 4318. Mismatching causes connection refused or silent drops.

### Debug mode

```bash
# See exporter startup, export attempts, and errors
RUST_LOG=opentelemetry=debug,opentelemetry_otlp=debug ./my-service
```

### Compile errors with `grpc-tonic` feature

The `tonic` and `opentelemetry-otlp` crates share gRPC dependencies. If versions conflict:

```bash
cargo update
cargo tree -d  # check for duplicate crate versions
```

Pin compatible versions in `Cargo.toml`:

```toml
[dependencies]
tonic = "0.12"
opentelemetry-otlp = { version = "0.31", features = ["grpc-tonic"] }
```

### Spans created but not exported

Check that `BatchSpanProcessor` is used (not `SimpleSpanProcessor`) and an OTLP exporter is configured:

```rust
// GOOD — batch exporter for production
let tracer_provider = SdkTracerProvider::builder()
    .with_batch_exporter(otlp_exporter)
    .build();

// BAD for production — simple exporter is synchronous; use for debugging only
// let tracer_provider = SdkTracerProvider::builder()
//     .with_simple_exporter(otlp_exporter)
//     .build();
```

### `log::` macros produce no OTel output

```rust
// Add to Cargo.toml: tracing-log = "0.2"

// Call at startup BEFORE any log:: macros fire:
tracing_log::LogTracer::init().expect("log bridge init failed");
```

### OTLP gRPC TLS for Tsuga

Port 443 requires TLS. With tonic, using `https://` scheme triggers TLS automatically:

```rust
// GOOD — TLS is automatic with https:// scheme; tonic uses system roots
opentelemetry_otlp::SpanExporter::builder()
    .with_tonic()
    .with_endpoint("https://ingest.<region>.tsuga.cloud:443")
    // No explicit TLS config needed
    .build()?;
```

```rust
// Local development without TLS
opentelemetry_otlp::SpanExporter::builder()
    .with_tonic()
    .with_endpoint("http://localhost:4317")  // insecure channel for http://
    .build()?;
```

## Shutdown / Flush

Rust's `BatchSpanProcessor` runs on a background Tokio task. On process exit, the provider's `shutdown()` method signals it to flush remaining spans.

**Basic shutdown (recommended):**

```rust
// Return the provider from init; call shutdown() before main exits
pub fn init_telemetry() -> SdkTracerProvider {
    let tracer_provider = SdkTracerProvider::builder()
        .with_batch_exporter(otlp_exporter)
        .build();
    global::set_tracer_provider(tracer_provider.clone());
    tracer_provider  // caller holds it until shutdown
}

// In main:
let tracer_provider = init_telemetry()?;
run_server().await;
tracer_provider.shutdown().expect("tracer provider shutdown failed");
```

**Signal handling:**

```rust
use tokio::signal;

tokio::select! {
    _ = signal::ctrl_c() => {},
    _ = signal::unix::signal(signal::unix::SignalKind::terminate())
        .unwrap().recv() => {},
}
tracer_provider.shutdown().expect("shutdown failed");
```

**Common shutdown mistakes:**

- Not calling `shutdown()` at all — last batch of spans (up to 5 s) is lost
- Dropping `SdkTracerProvider` before calling `shutdown()` — triggers abrupt stop, not graceful flush
- Calling `global::shutdown_tracer_provider()` without a short delay — async flush task may not complete; prefer `tracer_provider.shutdown()` which blocks until flush completes

## Resilience: Collector Unavailable

When the OTLP collector is unreachable, the Rust OTel SDK does **not** panic. Export errors are returned from the exporter future and handled by `BatchSpanProcessor` (retries then drops). The service continues running.

**Default behavior:** `opentelemetry-otlp` retries on transport failure. Errors are reported via the OTel error handler (default: print to stderr), not propagated to application code.

**Conditional setup:**

```rust
fn init_tracing(endpoint: Option<&str>) -> SdkTracerProvider {
    if let Some(ep) = endpoint {
        let exporter = opentelemetry_otlp::SpanExporter::builder()
            .with_http()
            .with_endpoint(ep)
            .build()
            .expect("failed to create exporter");
        SdkTracerProvider::builder()
            .with_batch_exporter(exporter)
            .build()
    } else {
        // No collector — functional no-op provider (spans created, nothing exported)
        SdkTracerProvider::builder().build()
    }
}
```

**Disable OTel:**

```bash
OTEL_SDK_DISABLED=true ./my-service
```
