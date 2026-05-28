# Distributed Context Propagation — Rust

> Last verified: 2026-03-23 | SDK: opentelemetry 0.31.0 / tracing-opentelemetry 0.32.1

> **For async messaging propagation (Kafka, AMQP, SQS):** See [async-messaging.md](async-messaging.md).

## Overview

Trace context must be explicitly propagated across service boundaries. The W3C TraceContext headers (`traceparent`, `tracestate`) carry the trace ID and span ID between services. In Rust, `tracing-opentelemetry` handles span creation, while `opentelemetry` provides the propagation API.

## Configuring Propagators at Init

Set the propagator at startup — before any spans are created:

```rust
use opentelemetry::global;
use opentelemetry_sdk::propagation::TraceContextPropagator;

// In init_telemetry():
global::set_text_map_propagator(TraceContextPropagator::new());
```

For B3 support (Zipkin interop or legacy systems only):

```toml
[dependencies]
opentelemetry-zipkin = "0.31"
```

```rust
use opentelemetry::propagation::TextMapCompositePropagator;
use opentelemetry_zipkin::Propagator as B3Propagator;

global::set_text_map_propagator(TextMapCompositePropagator::new(vec![
    Box::new(TraceContextPropagator::new()),
    Box::new(B3Propagator::new()),
]));
```

Use W3C TraceContext for all new services. Add B3 only when interoperating with Zipkin-instrumented services or an Istio/Envoy mesh configured for B3.

## Inbound: Server Context Extraction

### Axum — Custom Middleware

```rust
use axum::{
    extract::Request,
    middleware::{self, Next},
    response::Response,
};
use opentelemetry::global;
use opentelemetry_http::HeaderExtractor;
use tracing::Instrument;

async fn otel_middleware(request: Request, next: Next) -> Response {
    let parent_ctx = global::get_text_map_propagator(|propagator| {
        propagator.extract(&HeaderExtractor(request.headers()))
    });

    let span = tracing::info_span!(
        "http.server",
        "http.request.method" = %request.method(),
        "http.route" = %request.uri().path(),
    );

    {
        use tracing_opentelemetry::OpenTelemetrySpanExt;
        span.set_parent(parent_ctx);
    }

    next.run(request).instrument(span).await
}

// Register in router
let app = Router::new()
    .route("/users/{id}", get(get_user))
    .layer(axum::middleware::from_fn(otel_middleware));
```

```toml
[dependencies]
opentelemetry-http = "0.31"
```

### tonic (gRPC server)

tonic represents request metadata as a `MetadataMap` rather than an HTTP `HeaderMap`. The `HeaderExtractor` from `opentelemetry-http` acts as a bridge between tonic's metadata types and the OTel propagation API.

```rust
use opentelemetry::global;
use opentelemetry_http::HeaderExtractor;

fn extract_context_from_grpc<T>(request: &tonic::Request<T>) -> opentelemetry::Context {
    let metadata = request.metadata();
    let headers: http::HeaderMap = metadata.clone().into_headers();
    global::get_text_map_propagator(|prop| {
        prop.extract(&HeaderExtractor(&headers))
    })
}
```

## Outbound: Client Context Injection

### reqwest

```rust
use opentelemetry::global;
use opentelemetry_http::HeaderInjector;
use tracing_opentelemetry::OpenTelemetrySpanExt;

async fn call_downstream(url: &str) -> Result<String, reqwest::Error> {
    let mut headers = reqwest::header::HeaderMap::new();

    // Inject current span's context into outbound headers
    let cx = tracing::Span::current().context();
    global::get_text_map_propagator(|propagator| {
        propagator.inject_context(&cx, &mut HeaderInjector(&mut headers));
    });

    let response = reqwest::Client::new()
        .get(url)
        .headers(headers)
        .send()
        .await?;
    Ok(response.text().await?)
}
```

### tonic gRPC client

```rust
use opentelemetry::global;
use opentelemetry_http::HeaderInjector;
use tonic::metadata::MetadataMap;
use tracing_opentelemetry::OpenTelemetrySpanExt;

fn inject_context_into_grpc() -> MetadataMap {
    let mut metadata = MetadataMap::new();
    let cx = tracing::Span::current().context();

    let mut headers = http::HeaderMap::new();
    global::get_text_map_propagator(|propagator| {
        propagator.inject_context(&cx, &mut HeaderInjector(&mut headers));
    });

    for (key, value) in &headers {
        if let Ok(key) = tonic::metadata::MetadataKey::from_bytes(key.as_str().as_bytes()) {
            if let Ok(value) = tonic::metadata::MetadataValue::try_from(value.to_str().unwrap_or("")) {
                metadata.insert(key, value);
            }
        }
    }
    metadata
}
```

## Anti-Pattern: Do Not Merge Separate Workflows

```rust
// WRONG — sets producer's context as parent; merges workflows into one trace
{
    use tracing_opentelemetry::OpenTelemetrySpanExt;
    span.set_parent(producer_context);
}

// CORRECT — link to producer trace, start new root
let span = tracing::info_span!("process order");
{
    use tracing_opentelemetry::OpenTelemetrySpanExt;
    if producer_span_ctx.is_valid() {
        span.add_link(producer_span_ctx);  // link, not parent
    }
}
```

> **→ See [async-messaging.md](async-messaging.md)** for full Kafka, AMQP, and SQS patterns
> with span Links, semconv attributes, and async context propagation.

## Tsuga Trace Continuity Validation

After instrumenting propagation, verify parent/child linkage:

```bash
tsuga spans search --query "context.service.name:<caller-service>" --max-results 5
# Note traceId values from results
tsuga spans search --query "context.service.name:<callee-service> traceId:<trace-id>"
# parentSpanId on callee spans must match spanId from caller spans
```
