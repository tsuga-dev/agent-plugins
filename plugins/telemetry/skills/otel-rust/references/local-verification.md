# Local Verification — Rust

## Overview

Before routing telemetry to a production collector, verify Rust instrumentation by printing spans to stdout using the `opentelemetry-stdout` crate. For CLI tools and short-lived binaries, calling `provider.shutdown()` before the process exits is critical — Rust's ownership model does not guarantee flush on drop, and spans queued in the processor will be silently lost without an explicit shutdown call.

## Console Span Exporter

Add the `opentelemetry-stdout` crate to `Cargo.toml`:

```toml
[dependencies]
opentelemetry = "0.31"
opentelemetry_sdk = "0.31"
opentelemetry-stdout = { version = "0.31", features = ["trace"] }
```

Configure a tracer provider with the stdout exporter:

```rust
use opentelemetry::global;
use opentelemetry::trace::Tracer;
use opentelemetry_sdk::trace::{self as sdktrace, SdkTracerProvider};
use opentelemetry_stdout::SpanExporter;

fn init_tracer() -> SdkTracerProvider {
    let exporter = SpanExporter::default();

    let provider = SdkTracerProvider::builder()
        .with_simple_exporter(exporter) // SimpleSpanProcessor
        .build();

    global::set_tracer_provider(provider.clone());
    provider
}
```

Each finished span is printed as JSON to stdout, including trace ID, span ID, parent span ID, name, kind, attributes, events, and timing.

⚠️ **Format stability:** The `opentelemetry-stdout` output schema is **not stable** and does not
guarantee OTLP JSON format. Do not parse this output in automated tests — use the in-memory exporter
(`InMemorySpanExporterBuilder`) for span assertions instead — see `references/testing.md`.
This exporter is for human inspection only.

## SimpleSpanProcessor vs BatchSpanProcessor

`with_simple_exporter` wraps the exporter in a `SimpleSpanProcessor`. `with_batch_exporter` uses `BatchSpanProcessor` with a Tokio runtime.

| | `with_simple_exporter` / `SimpleSpanProcessor` | `with_batch_exporter` / `BatchSpanProcessor` |
|---|---|---|
| Export timing | Synchronous, on span end | Async, Tokio background task |
| Local testing | Preferred — spans appear immediately | Requires `shutdown()` to flush; drops spans on exit |
| Production | Not recommended for high-throughput | Correct choice |

Always use `with_simple_exporter` during local development. The synchronous export means each span is written before the next line of code runs, making the output predictable.

## Short-Lived Processes and CLI Tools

Rust's `Drop` trait is not guaranteed to flush async exporters. Always call `provider.shutdown()` explicitly. Without it, buffered spans are dropped when the process exits.

```rust
use opentelemetry::global;
use opentelemetry::trace::{Tracer, TracerProvider as _};
use opentelemetry_sdk::trace::SdkTracerProvider;
use opentelemetry_stdout::SpanExporter;
use std::time::Duration;
use tokio::time::timeout;

#[tokio::main]
async fn main() {
    let provider = init_tracer();

    let tracer = global::tracer("my-cli");

    tracer.in_span("cli.run", |cx| {
        process_records();
    });

    // Shutdown with timeout — critical for CLI tools
    let shutdown_result = timeout(
        Duration::from_secs(5),
        tokio::task::spawn_blocking(move || provider.shutdown()),
    )
    .await;

    if let Err(_) = shutdown_result {
        eprintln!("tracer shutdown timed out");
    }
}
```

**The `tokio::time::timeout` pattern** ensures the process does not hang indefinitely if the exporter is unresponsive. For `SimpleSpanProcessor`, the shutdown is synchronous and completes immediately. For `BatchSpanProcessor`, the timeout is essential.

## Synchronous Shutdown Pattern for Non-async Contexts

If your binary does not use `async` throughout, use `block_on` to drive the shutdown future:

```rust
fn main() {
    let provider = init_tracer();

    // ... create spans synchronously ...

    let rt = tokio::runtime::Runtime::new().unwrap();
    rt.block_on(async {
        if let Err(e) = provider.shutdown() {
            eprintln!("shutdown error: {e}");
        }
    });
}
```

## OTEL_TRACES_EXPORTER Environment Variable

The Rust OTel SDK does not support `OTEL_TRACES_EXPORTER=console` natively. Configure the `opentelemetry-stdout` exporter explicitly in code. To switch between local and production exporters based on environment:

```rust
use std::env;

fn init_tracer() -> SdkTracerProvider {
    let builder = SdkTracerProvider::builder();

    match env::var("OTEL_TRACES_EXPORTER").as_deref() {
        Ok("console") | Ok("stdout") => {
            builder
                .with_simple_exporter(opentelemetry_stdout::SpanExporter::default())
                .build()
        }
        _ => {
            // Configure OTLP exporter for production
            let exporter = opentelemetry_otlp::SpanExporter::builder()
                .with_tonic()
                .build()
                .expect("failed to build OTLP exporter");
            builder.with_batch_exporter(exporter).build()
        }
    }
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

Point the Rust OTLP exporter at the local collector:

```toml
[dependencies]
opentelemetry-otlp = { version = "0.31", features = ["grpc-tonic"] }
tonic = "0.12"
```

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
OTEL_SERVICE_NAME=my-service \
cargo run
```
