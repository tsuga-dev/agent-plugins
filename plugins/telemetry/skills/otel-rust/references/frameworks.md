# Framework-Specific Recipes — Rust

## Axum

Axum integrates with OTel via `tower-http`'s `TraceLayer`, which creates spans using `tracing`. Combined with `tracing-opentelemetry`, these become OTel spans.

```toml
[dependencies]
axum = "0.8"
tower-http = { version = "0.6", features = ["trace"] }
tracing = "0.1"
tracing-opentelemetry = "0.32.1"
opentelemetry = "0.31.0"
opentelemetry_sdk = "0.31.0"
opentelemetry-otlp = { version = "0.31.1", features = ["grpc-tonic"] }
tracing-subscriber = { version = "0.3", features = ["env-filter", "json"] }
tokio = { version = "1", features = ["full"] }
```

```rust
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
    routing::get,
    Router,
};
use tower_http::trace::TraceLayer;
use tracing::{error, info, instrument};
use opentelemetry::global;

#[derive(Clone)]
struct AppState {
    db: DatabasePool,
}

#[instrument(skip(state), fields(user.id = %user_id))]
async fn get_user(
    Path(user_id): Path<String>,
    State(state): State<AppState>,
) -> Result<Json<User>, StatusCode> {
    info!("fetching user");

    match state.db.get_user(&user_id).await {
        Ok(user) => {
            info!(user.found = true, "user found");
            Ok(Json(user))
        }
        Err(e) => {
            error!(error = %e, "user not found");
            Err(StatusCode::NOT_FOUND)
        }
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    init_telemetry()?;

    let state = AppState { db: DatabasePool::new().await };

    let app = Router::new()
        .route("/users/{id}", get(get_user))
        .route("/health", get(|| async { StatusCode::OK }))
        .layer(
            TraceLayer::new_for_http()
                .make_span_with(|request: &axum::http::Request<_>| {
                    tracing::info_span!(
                        "http.server",
                        http.method = %request.method(),
                        http.route = %request.uri().path(),
                        http.status_code = tracing::field::Empty,
                        otel.name = format!("{} {}", request.method(), request.uri().path()),
                    )
                })
                .on_response(|response: &axum::http::Response<_>, latency, span: &tracing::Span| {
                    span.record("http.status_code", response.status().as_u16());
                    tracing::info!(
                        latency_ms = latency.as_millis(),
                        "response sent"
                    );
                })
                .on_failure(|error, _latency, span: &tracing::Span| {
                    tracing::error!(error = %error, "request failed");
                }),
        )
        .with_state(state);

    axum::serve(
        tokio::net::TcpListener::bind("0.0.0.0:8080").await?,
        app,
    ).await?;

    shutdown_telemetry().await;
    Ok(())
}
```

## actix-web

```toml
[dependencies]
actix-web = "4"
tracing-actix-web = "0.7"
tracing = "0.1"
```

```rust
use actix_web::{get, web, App, HttpServer, HttpResponse};
use tracing::instrument;
use tracing_actix_web::TracingLogger;

#[get("/users/{id}")]
#[instrument(fields(user.id = %id))]
async fn get_user(id: web::Path<String>) -> HttpResponse {
    match fetch_user(&id).await {
        Ok(user) => HttpResponse::Ok().json(user),
        Err(e) => {
            tracing::error!(error = %e, "failed to fetch user");
            HttpResponse::NotFound().finish()
        }
    }
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    init_telemetry().expect("failed to init telemetry");

    HttpServer::new(|| {
        App::new()
            .wrap(TracingLogger::default())  // creates OTel spans via tracing
            .service(get_user)
    })
    .bind("0.0.0.0:8080")?
    .run()
    .await?;

    shutdown_telemetry().await;
    Ok(())
}
```

`tracing-actix-web::TracingLogger` creates a `tracing` span for every request. Since `tracing-opentelemetry` bridges `tracing` spans to OTel, these appear as OTel spans automatically.

## tonic (gRPC)

```toml
[dependencies]
tonic = "0.12"
prost = "0.13"
tower = "0.4"
tower-http = { version = "0.6", features = ["trace"] }
```

```rust
use tonic::{transport::Server, Request, Response, Status};
use tracing::instrument;

pub struct MyService;

#[tonic::async_trait]
impl MyServiceTrait for MyService {
    #[instrument(skip(self, request), fields(user_id = ?request.get_ref().user_id))]
    async fn get_user(
        &self,
        request: Request<GetUserRequest>,
    ) -> Result<Response<GetUserResponse>, Status> {
        let user_id = request.into_inner().user_id;

        match fetch_user(user_id).await {
            Ok(user) => Ok(Response::new(GetUserResponse {
                id: user.id,
                name: user.name,
            })),
            Err(e) => {
                tracing::error!(error = %e, "failed to fetch user");
                Err(Status::not_found("user not found"))
            }
        }
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    init_telemetry()?;

    let addr = "[::1]:50051".parse()?;
    let service = MyService;

    Server::builder()
        .layer(
            tower::ServiceBuilder::new()
                .layer(tower_http::trace::TraceLayer::new_for_grpc())
        )
        .add_service(MyServiceServer::new(service))
        .serve(addr)
        .await?;

    shutdown_telemetry().await;
    Ok(())
}
```

## Span Naming in Rust

Follow these conventions for `#[instrument]`:

```rust
// Business logic
#[instrument(name = "order.process")]
async fn process_order(order: &Order) { ... }

// Database operation
#[instrument(name = "db.get_user", skip(pool))]
async fn get_user(pool: &Pool, id: i64) { ... }

// External service call
#[instrument(name = "http.call.payment_service")]
async fn charge_card(amount: f64) { ... }
```

Keep span names low-cardinality. Use span attributes (fields) for dynamic values:

```rust
#[instrument(fields(user.id = %user_id, order.amount = amount))]
async fn process_payment(user_id: u64, amount: f64) { ... }
```

## Error Recording Pattern

```rust
use tracing::{error, instrument};

#[instrument(err)]
async fn risky_operation() -> Result<(), MyError> {
    // Errors are automatically recorded on the span via #[instrument(err)]
    do_something().await?;
    Ok(())
}

// Or manually:
#[instrument]
async fn another_operation() -> Result<(), MyError> {
    match do_something().await {
        Ok(v) => Ok(v),
        Err(e) => {
            error!(error = %e, error.kind = ?e, "operation failed");
            Err(e)
        }
    }
}

## Lifecycle Logging

Structured log events correlated with OTel trace context using `tracing` + `tracing-opentelemetry`.

```rust
use opentelemetry::trace::TraceContextExt;
use tracing::{info, instrument};
use tracing_opentelemetry::OpenTelemetrySpanExt;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

fn init_logging() {
    tracing_subscriber::registry()
        .with(EnvFilter::from_default_env())
        .with(tracing_subscriber::fmt::layer().json())  // structured JSON output
        .with(tracing_opentelemetry::layer())            // bridges tracing -> OTel
        .init();
}

// --- Service startup ---
fn log_startup() {
    info!(
        version = std::env::var("APP_VERSION").unwrap_or_default(),
        environment = std::env::var("DEPLOYMENT_ENV").unwrap_or_default(),
        otlp_endpoint = std::env::var("OTEL_EXPORTER_OTLP_ENDPOINT").unwrap_or_default(),
        "service starting"
    );
}

// --- Request lifecycle (axum middleware) ---
// tracing's #[instrument] macro automatically creates spans and correlates logs
#[instrument(fields(method = %req.method(), path = %req.uri().path()))]
async fn handle_request(req: axum::extract::Request) -> impl axum::response::IntoResponse {
    info!("request received");
    // ... handler logic ...
    info!(status = 200, "request completed");
}

// --- Graceful shutdown ---
async fn shutdown(provider: SdkTracerProvider) {
    info!("service shutting down");
    if let Err(e) = provider.shutdown() {
        tracing::error!(error = %e, "otel shutdown error");
    }
    info!("otel provider shut down");
}
```

> `tracing-opentelemetry` bridges the `tracing` ecosystem to OTel — spans created by `#[instrument]` or `tracing::span!` become OTel spans, and log events inside those spans include `trace_id` and `span_id` in the OTLP log records.

> **Beta:** Rust OTel SDK is pre-1.0. The `tracing-opentelemetry` bridge is the recommended pattern for production Rust services.

## Microservices Propagation Pattern

Two-service HTTP call: caller injects trace context, callee extracts and creates a child span.

**Caller service (outbound HTTP with reqwest):**

```rust
use opentelemetry::global;
use opentelemetry_http::HeaderInjector;
use reqwest::Client;
use tracing::instrument;

#[instrument]
async fn call_downstream(user_id: &str) -> anyhow::Result<serde_json::Value> {
    let client = Client::new();

    // Build request and inject W3C trace context into headers
    let mut headers = reqwest::header::HeaderMap::new();
    let cx = opentelemetry::Context::current();
    global::get_text_map_propagator(|propagator| {
        propagator.inject_context(&cx, &mut HeaderInjector(&mut headers));
    });

    let response = client
        .get(format!("http://user-service/users/{}", user_id))
        .headers(headers)
        .send()
        .await?;

    Ok(response.json().await?)
}
```

**Callee service (inbound HTTP with axum):**

```rust
use axum::{extract::Path, http::HeaderMap};
use opentelemetry::global;
use opentelemetry_http::HeaderExtractor;
use opentelemetry::trace::Tracer;

async fn get_user(headers: HeaderMap, Path(user_id): Path<String>) -> impl axum::response::IntoResponse {
    // Extract W3C trace context from inbound headers
    let parent_cx = global::get_text_map_propagator(|propagator| {
        propagator.extract(&HeaderExtractor(&headers))
    });

    let tracer = global::tracer("user-service");
    let _span = tracer
        .span_builder("handle.get_user")
        .start_with_context(&tracer, &parent_cx);  // child of caller's span

    // ... handler logic — this span is linked to the caller's trace
    axum::Json(serde_json::json!({ "id": user_id, "name": "Alice" }))
}
```

> With `tracing-opentelemetry`, use `#[instrument]` on the caller and `tracing_opentelemetry::OpenTelemetrySpanExt::set_parent()` on the callee for a more idiomatic integration.

**Validate in Tsuga:** Confirm the callee span's `parent_span_id` matches the caller's span ID in the same trace.
```
