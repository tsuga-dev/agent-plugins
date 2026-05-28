# Audit Checklist — Rust OTel

> Last verified: 2026-03-23 | SDK: opentelemetry 0.31.0 / opentelemetry-sdk 0.31.0 / tracing-opentelemetry 0.32.1

## Signs OTel Is Already Set Up

Look for these indicators before adding instrumentation:

- `opentelemetry` and `tracing-opentelemetry` in `Cargo.toml` dependencies
- `tracing_subscriber::registry().with(otel_layer)` pattern in main or initialization code
- `SdkTracerProvider::shutdown()` or `global::shutdown_tracer_provider()` call on exit
- `#[tracing::instrument]` macros on async functions
- `OTEL_SERVICE_NAME` or `OTEL_EXPORTER_OTLP_ENDPOINT` in environment config

## Dependency Check

```bash
cargo tree | grep opentelemetry
cargo tree | grep tracing
```

Expected minimum versions:

| Crate | Minimum version |
|-------|----------------|
| `opentelemetry` | 0.31.0 |
| `opentelemetry_sdk` | 0.31.0 |
| `opentelemetry-otlp` | 0.31.1 |
| `opentelemetry-appender-tracing` | 0.31.0 |
| `tracing-opentelemetry` | 0.32.1 |
| `tracing-subscriber` | 0.3.x (with `env-filter`, `json` features) |

> **Pre-1.0 stability note:** The Rust OTel ecosystem is pre-1.0. APIs break between minor versions — always check crate changelogs before upgrading.

## Anti-Patterns to Flag

**1. Not calling shutdown**

```rust
// WRONG — process exits without flushing in-flight spans
#[tokio::main]
async fn main() {
    init_telemetry().unwrap();
    run_server().await;
    // no shutdown — last spans (up to 5 s) lost
}

// CORRECT
#[tokio::main]
async fn main() {
    let tracer_provider = init_telemetry().unwrap();
    run_server().await;
    tracer_provider.shutdown().expect("shutdown failed");
}
```

**2. Transport used outside Tokio runtime**

```rust
// WRONG — grpc-tonic / reqwest-client transports need Tokio runtime
fn main() {
    let exporter = opentelemetry_otlp::SpanExporter::builder()
        .with_tonic()
        .build()  // panics: "no tokio runtime"
        .unwrap();
}

// CORRECT — init inside #[tokio::main] or active Tokio context
#[tokio::main]
async fn main() {
    let exporter = opentelemetry_otlp::SpanExporter::builder()
        .with_tonic()
        .build()
        .unwrap();
}
```

**3. `log::` macros without `LogTracer::init()`**

```rust
// WRONG — log:: macros produce no OTel output
log::info!("something happened");

// CORRECT — add to Cargo.toml: tracing-log = "0.2"
// Call once at startup:
tracing_log::LogTracer::init().expect("failed to init log bridge");
// Now log::info!() routes through tracing → OTel
```

**4. `span.enter()` across `.await` points**

```rust
// WRONG — guard held across await corrupts async context propagation
let span = tracing::info_span!("my.op");
let _guard = span.enter();
some_future.await;  // guard still held — BAD

// CORRECT — use Instrument trait or #[instrument]
use tracing::Instrument;
some_future.instrument(tracing::info_span!("my.op")).await;
```

**5. Not enabling `env-filter` on `tracing-subscriber`**

```toml
# WRONG — no filter; all spans including debug level exported
tracing-subscriber = "0.3"

# CORRECT
tracing-subscriber = { version = "0.3", features = ["env-filter", "json"] }
```

```rust
// CORRECT — read RUST_LOG at runtime
tracing_subscriber::registry()
    .with(tracing_subscriber::EnvFilter::from_default_env())
    .with(otel_layer)
    .init();
```

**6. Dropping `SdkTracerProvider` too early**

```rust
// WRONG — tracer_provider dropped at end of init function; batch exporter shuts down
pub fn init_telemetry() {
    let tracer_provider = SdkTracerProvider::builder().build();
    global::set_tracer_provider(tracer_provider.clone());
    // tracer_provider dropped here — no spans exported
}

// CORRECT — return provider; caller keeps it alive until shutdown
pub fn init_telemetry() -> SdkTracerProvider {
    let tracer_provider = SdkTracerProvider::builder().build();
    global::set_tracer_provider(tracer_provider.clone());
    tracer_provider
}
```

**7. Metrics without an explicit reader**

```rust
// WRONG — no reader means metrics are never exported
let meter_provider = SdkMeterProvider::builder().build();

// CORRECT — attach a PeriodicReader
let metric_reader = PeriodicReader::builder(metric_exporter, Tokio).build();
let meter_provider = SdkMeterProvider::builder()
    .with_reader(metric_reader)
    .build();
```

**8. Missing `deployment.environment.name`**

```bash
# CORRECT — set via env var
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production

# WRONG — using deprecated key
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production
```

## 11-Step Live Audit Workflow

Run these steps in order against a running service. Cite evidence for each finding.

**Step 1 — Confirm signals are arriving**

```bash
tsuga spans search --query "context.service.name:<service>" --max-results 5
tsuga logs search --query "context.service.name:<service> trace_id:*" --max-results 3
tsuga metrics list --filter "service.name=<service>"
```

Evidence required: output from each command or explicit "0 results" finding.

**Step 2 — Check resource attributes**

```bash
tsuga spans search --query "context.service.name:<service>" --max-results 1
# Inspect: service.version, deployment.environment.name present?
```

**Step 3 — Check service name source (env var vs hardcoded)**

```bash
kubectl exec -n <ns> <pod> -- env | grep OTEL_SERVICE_NAME
# or: docker inspect <container> | grep OTEL_SERVICE_NAME
```

Expected: `OTEL_SERVICE_NAME=<service>` — not hardcoded in `Resource::builder().with_service_name(...)`.

**Step 4 — Check crate versions**

```bash
cargo tree | grep opentelemetry
cargo tree | grep tracing-opentelemetry
```

Expected: `opentelemetry` 0.31.0, `tracing-opentelemetry` 0.32.1. If older: update and redeploy (note: 0.27→0.31 contains breaking changes — review CHANGELOG).

**Step 5 — Check transport runtime compatibility**

Ensure exporter initialization happens within a Tokio runtime context when using `grpc-tonic` or `reqwest-client` transports.

**Step 6 — Check span naming quality**

```bash
tsuga spans search --query "context.service.name:<service>" --max-results 20
# Look for: function names (get_user_orders), format strings (/users/123), missing verb-object pattern
```

**Step 7 — Check span status correctness**

```bash
tsuga spans search --query "context.service.name:<service> status:ERROR" --max-results 10
# Verify: ERROR spans have a description; SERVER 4xx spans are UNSET not ERROR
```

**Step 8 — Check metric naming**

```bash
tsuga metrics list --filter "service.name=<service>"
# Look for: underscore names (http_requests), units in name (_ms, _bytes), service name as prefix
```

If source code path is available, also check instrument type:
- Description containing "current", "active", "open", "in-flight", or "pending" → must use UpDownCounter (not Counter)
- Description containing "duration", "latency", "time", or "size" → must use Histogram (not Counter or Gauge)

**Step 9 — Check log-trace correlation**

```bash
tsuga logs search --query "context.service.name:<service> trace_id:*" --max-results 5
# Verify: trace_id field present on log records; span_id present
```

**Step 10 — Check for `span.enter()` across await points (code review)**

```bash
grep -rn "\.enter()" src/
# Flag any .enter() call followed by an .await on the next line or inside a block
# CORRECT pattern: .instrument(span) or #[instrument]
```

**Step 11 — Check exporter configuration**

```bash
kubectl exec -n <ns> <pod> -- env | grep OTEL_EXPORTER
```

Expected:
- `OTEL_EXPORTER_OTLP_ENDPOINT` set (no hardcoded `.with_endpoint(...)` in code)
- `OTEL_EXPORTER_OTLP_PROTOCOL` NOT expected (set by Cargo feature at compile time)

## Tsuga Verification Commands

```bash
# Check for traces
tsuga spans search --query "context.service.name:<your-service>" --max-results 5

# Check for log-trace correlation
tsuga logs search --query "context.service.name:<your-service> trace_id:*" --max-results 3

# Check for metrics
tsuga metrics list --filter "service.name=<your-service>"
```

If no spans appear:
1. Check `OTEL_EXPORTER_OTLP_ENDPOINT` — for gRPC use `http://localhost:4317`, for HTTP use `http://localhost:4318`
2. Add `RUST_LOG=opentelemetry=debug` to see exporter startup and export attempts
3. Verify `SdkTracerProvider` is not dropped prematurely (return it from init)
4. Confirm `global::set_tracer_provider(tracer_provider.clone())` is called during init

## Evidence Requirements

Each audit finding must include:
- **Command used** (CLI command or grep)
- **File path + line number** (for code findings)
- **Observed value** (what was found)
- **Expected value** (what it should be)

## Output Template

```
## Audit: <service-name> — <date>

### Signals Present
- Traces: [yes/no] — tsuga spans search returned N results
- Logs: [yes/no] — tsuga logs search returned N results
- Metrics: [yes/no] — tsuga metrics list returned N entries

### Resource Attributes
- service.name: [value] — source: [env var / hardcoded]
- service.version: [value or MISSING]
- deployment.environment.name: [value or MISSING]

### Findings
1. [Finding] — Evidence: [command + output or file:line]
   Fix: [specific action]

### Version Check
- opentelemetry: [version]
- tracing-opentelemetry: [version]
```

## Instrumentation Quality Rules

**A1 — Every service boundary has a span.** Each inbound HTTP/gRPC handler and each outbound call must produce a span. No gaps at service edges.

**A2 — Span names are low-cardinality.** No user IDs, request IDs, or raw URL paths in span names. Use `{verb} {template}` pattern; override `#[instrument]` default name when needed.

**A3 — Error spans have descriptions.** Every span with `Status::error(...)` must have a non-empty description string.

**A4 — Resource attributes are externally configurable.** `service.name`, `service.version`, and `deployment.environment.name` must be settable via env vars without recompiling.

**A5 — No orphan spans.** Every span except root must have a parent. Scheduled jobs and queue consumers must create a root span, not inherit an unrelated parent.
