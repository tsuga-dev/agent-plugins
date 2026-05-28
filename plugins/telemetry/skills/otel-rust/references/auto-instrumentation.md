# Auto-Instrumentation — Rust

## Overview

Rust does not support bytecode injection or dynamic patching. "Auto-instrumentation" in Rust means using the `#[instrument]` macro from the `tracing` crate, combined with framework-level middleware/layers that create spans for inbound requests. The `tracing-opentelemetry` bridge then exports those spans as OTel data.

## The `#[instrument]` Macro

The `#[instrument]` macro from the `tracing` crate is the primary auto-instrumentation primitive in Rust. It creates a span for every function call, capturing arguments as span attributes.

```toml
# Cargo.toml
[dependencies]
tracing = "0.1"
tracing-opentelemetry = "0.32.1"
```

```rust
use tracing::{info, instrument};

// Basic usage — creates a span named "fetch_user" for each call
#[instrument]
async fn fetch_user(user_id: u64) -> Result<User, Error> {
    info!(user_id, "fetching user");
    db.get_user(user_id).await
}

// Capture specific fields as span attributes
#[instrument(fields(user.id = %user_id, http.method = "GET"))]
async fn handle_get_user(user_id: u64) -> impl axum::response::IntoResponse {
    // ...
}

// Skip sensitive or large arguments
#[instrument(skip(password, db))]
async fn authenticate(username: &str, password: &str, db: &Database) -> bool {
    // ...
}

// Custom span name
#[instrument(name = "order.validate")]
async fn validate_order(order: &Order) -> Result<(), ValidationError> {
    // ...
}

// Return value recorded as span event
#[instrument(ret)]
fn compute_price(items: &[Item]) -> f64 {
    items.iter().map(|i| i.price).sum()
}

// Error recorded on span automatically
#[instrument(err)]
async fn risky_operation() -> Result<(), MyError> {
    do_something_risky().await
}
```

Use `#[instrument]` when you want a span for an entire function — zero boilerplate, automatic argument capture. Use `info_span!` (with `.instrument()` for async) when you need a span for a sub-block within a function, or want to conditionally instrument without annotating the function itself.

## Framework Middleware

### Axum (tower-http + OpenTelemetry)

```bash
cargo add tower-http --features trace
cargo add tracing-opentelemetry
```

```rust
use axum::{Router, routing::get};
use tower_http::trace::TraceLayer;

let app = Router::new()
    .route("/users/{id}", get(get_user_handler))
    .layer(
        TraceLayer::new_for_http()
            .make_span_with(|request: &axum::http::Request<_>| {
                tracing::info_span!(
                    "http.server",
                    http.method = %request.method(),
                    http.target = %request.uri(),
                    http.status_code = tracing::field::Empty,
                )
            })
            .on_response(|response: &axum::http::Response<_>, _latency, span: &tracing::Span| {
                span.record("http.status_code", response.status().as_u16());
            })
    );
```

### actix-web (tracing middleware)

```toml
[dependencies]
tracing-actix-web = "0.7"
```

```rust
use actix_web::{web, App, HttpServer};
use tracing_actix_web::TracingLogger;

HttpServer::new(|| {
    App::new()
        .wrap(TracingLogger::default())  // creates spans for all requests
        .service(web::resource("/users/{id}").route(web::get().to(get_user)))
})
.bind("0.0.0.0:8080")?
.run()
.await
```

### tonic (gRPC)

```toml
[dependencies]
tonic = "0.12"
tower = "0.4"
```

```rust
use tonic::transport::Server;

// Wrap gRPC service with tower tracing middleware
Server::builder()
    .layer(
        tower::ServiceBuilder::new()
            .layer(tower_http::trace::TraceLayer::new_for_grpc())
    )
    .add_service(my_service)
    .serve(addr)
    .await?;
```

## What Gets Covered with `#[instrument]`

- Any async or sync function annotated with `#[instrument]`
- Span attributes from function arguments (by default, all `Debug`-implementing args)
- Error recording when `#[instrument(err)]` is used
- Return value recording when `#[instrument(ret)]` is used

`#[instrument]` has near-zero overhead when the span is filtered out by `RUST_LOG`. In hot code paths that *are* sampled and called thousands of times per second, each call allocates span metadata — benchmark before annotating tight loops, and prefer instrumenting at a higher-level function that covers the full batch.

## What Needs Manual Instrumentation

- Framework-level request/response spans (handled by `TraceLayer`/`TracingLogger`)
- Database queries — the `sqlx` and `diesel` query builders don't have OTel integration; wrap with manual spans or use `tracing` spans around queries
- Message queue consumers — extract context manually and create spans
- External HTTP client calls — `reqwest` does not auto-inject `traceparent`; inject manually

## Database Spans (sqlx)

```rust
use opentelemetry::{global, KeyValue};
use tracing::{info_span, instrument};

#[instrument(skip(pool))]
async fn get_user(pool: &sqlx::PgPool, user_id: i64) -> Result<User, sqlx::Error> {
    // Create a manual span for the query
    let span = info_span!(
        "db.query",
        db.system = "postgresql",
        db.operation = "SELECT",
        db.sql.table = "users",
    );
    let _guard = span.enter();

    sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_one(pool)
        .await
}
```

## Async Pitfall: Never `span.enter()` Across `.await`

```rust
// WRONG — enters span before await; span may be held across thread switch
let span = info_span!("my.op");
let _guard = span.enter();
some_async_call().await;  // guard held across await — corrupts context

// CORRECT — use Instrument::instrument() for async
use tracing::Instrument;
async_operation()
    .instrument(info_span!("my.op"))
    .await;

// OR use #[instrument] macro
#[instrument]
async fn my_function() {
    some_async_call().await;
}
```

## Verifying Auto-Instrumentation

```bash
RUST_LOG=info cargo run
# Make requests, then:
tsuga spans search --query "context.service.name:my-service" --max-results 5
# Look for "http.server", function name spans from #[instrument]
```
