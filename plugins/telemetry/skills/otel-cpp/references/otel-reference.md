# OTel Reference — C++

> **Last verified:** 2026-03-23 | SDK: `opentelemetry-cpp` 1.26.0

Canonical reference for OpenTelemetry instrument types, naming rules, and telemetry best practices. C++-specific SDK API and environment variable details.

> For authoritative rules: https://opentelemetry.io/docs/specs/otel/metrics/supplementary-guidelines/ and https://opentelemetry.io/docs/specs/semconv/

---

## Instrument Types

| Instrument | Use case | Monotonic? | Example |
|---|---|---|---|
| **Counter** | Counts discrete events that only increase | Yes | `http.server.request.count`, `db.client.errors` |
| **UpDownCounter** | Fluctuating current values | No | `db.client.connections.usage`, `messaging.client.consumed.messages` |
| **Histogram** | Distributions of values (latency, size) | No | `http.server.request.duration`, `http.server.request.body.size` |
| **Synchronous Gauge** | Current spot value recorded imperatively (call `Record()` per measurement) | No | Per-request cache hit ratio, current temperature reading |
| **Observable Counter** | Monotonically increasing total, sampled at collection | Yes | Total bytes sent (read from system counter) |
| **Observable UpDownCounter** | Fluctuating total, sampled at collection | No | Active thread count, heap memory usage |
| **Observable Gauge** | Spot measurement at collection time via callback | No | CPU utilization (%), current queue depth |

> Unsure which type fits? → `signal-choice-advisor`

---

## C++ Instrument API

| Instrument | SDK Method | Notes |
|---|---|---|
| Counter (double) | `meter->CreateDoubleCounter(name, description, unit)` | Returns `std::unique_ptr<DoubleCounter>` |
| Counter (uint64) | `meter->CreateUInt64Counter(name, description, unit)` | Integer variant |
| Histogram (double) | `meter->CreateDoubleHistogram(name, description, unit)` | Use for latency/duration |
| Histogram (uint64) | `meter->CreateUInt64Histogram(name, description, unit)` | Integer variant |
| UpDownCounter (double) | `meter->CreateDoubleUpDownCounter(name, description, unit)` | Supports negative delta |
| UpDownCounter (int64) | `meter->CreateInt64UpDownCounter(name, description, unit)` | Integer variant |
| Synchronous Gauge (double) | `meter->CreateDoubleGauge(name, description, unit)` | Added in v1.18.0; call `->Record(value, attrs)` per measurement |
| Observable Gauge (double) | `meter->CreateDoubleObservableGauge(name, description, unit)` | Register callback via `->AddCallback(cb, state)` |
| Observable Counter (double) | `meter->CreateDoubleObservableCounter(name, description, unit)` | — |
| Observable UpDownCounter (double) | `meter->CreateDoubleObservableUpDownCounter(name, description, unit)` | — |

**Recording values:**
```cpp
auto counter = meter->CreateDoubleCounter("requests.total", "Total requests", "{request}");
counter->Add(1.0, {{"method", "GET"}, {"status", "200"}}, context::RuntimeContext::GetCurrent());
```

Get `meter` via: `auto meter = metrics_api::Provider::GetMeterProvider()->GetMeter("my-service", "1.0.0")` (second param is version).

As of v1.15+, the C++ SDK auto-reads `OTEL_*` exporter vars (e.g., `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_HEADERS`) in the exporter options constructors. Resource attributes (`OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES`) still need `std::getenv()` for use in `Resource::Create()`.

> **Cardinality warning:** Do not use per-request values in metric attribute sets. Use low-cardinality values only.

---

## Environment Variables Reference

> As of v1.15+, the C++ SDK exporter options constructors auto-read `OTEL_*` vars listed below. Resource-level vars (`OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES`) and sampler/propagator vars still require manual `std::getenv()` handling.

| Variable | Purpose | Required? | Default (per spec) | SDK auto-reads? | Notes |
|---|---|---|---|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP endpoint URL | **yes** | `http://localhost:4318` | **yes** (v1.15+) | Read by exporter options constructors |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | Transport protocol | no | `http/protobuf` | **no** | Set by which exporter class you link and instantiate |
| `OTEL_EXPORTER_OTLP_HEADERS` | Auth/custom headers | depends | (none) | **yes** (v1.15+) | Read by exporter options constructors |
| `OTEL_EXPORTER_OTLP_TIMEOUT` | Export timeout (ms) | no | `10000` | **yes** (v1.15+) | Read by exporter options constructors |
| `OTEL_EXPORTER_OTLP_COMPRESSION` | Compression | no | `none` | **yes** (v1.15+) | Read by exporter options constructors |
| `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | Traces-only endpoint | no | inherits base endpoint | **yes** (v1.15+) | Signal-specific override |
| `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT` | Metrics-only endpoint | no | inherits base endpoint | **yes** (v1.15+) | Signal-specific override |
| `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` | Logs-only endpoint | no | inherits base endpoint | **yes** (v1.15+) | Signal-specific override |
| `OTEL_TRACES_EXPORTER` | Traces exporter type | no | `otlp` | **no** | Exporter type is set at link time |
| `OTEL_METRICS_EXPORTER` | Metrics exporter type | no | `none` | **no** | Exporter type is set at link time |
| `OTEL_LOGS_EXPORTER` | Logs exporter type | no | `otlp` | **no** | Exporter type is set at link time |
| `OTEL_SERVICE_NAME` | Service name | **yes** | (none) | **no** | `std::getenv("OTEL_SERVICE_NAME")` for `Resource::Create()` |
| `OTEL_RESOURCE_ATTRIBUTES` | Additional resource attrs | no | (none) | **no** | Parse manually: split `k=v,k=v` and add to `Resource::Create()` |
| `OTEL_SDK_DISABLED` | Disable SDK (noop) | no | `false` | **no** | Check `std::getenv("OTEL_SDK_DISABLED")` at init |
| `OTEL_TRACES_SAMPLER` | Sampler type | no | `parentbased_always_on` | **no** | Instantiate the desired sampler class manually |
| `OTEL_TRACES_SAMPLER_ARG` | Sampler argument | no | (sampler-specific) | **no** | Read and pass to sampler constructor |
| `OTEL_PROPAGATORS` | Context propagators | no | `tracecontext,baggage` | **no** | Register propagators manually at init |
| `OTEL_BSP_SCHEDULE_DELAY` | BSP export interval (ms) | no | `5000` | **no** | Set via `BatchSpanProcessorOptions.schedule_delay_millis` |
| `OTEL_BSP_MAX_QUEUE_SIZE` | BSP max queue | no | `2048` | **no** | Set via `BatchSpanProcessorOptions.max_queue_size` |
| `OTEL_BSP_MAX_EXPORT_BATCH_SIZE` | BSP max batch | no | `512` | **no** | Set via `BatchSpanProcessorOptions.max_export_batch_size` |

---

## Temporality

| Mode | Meaning | Tsuga behavior |
|---|---|---|
| **Cumulative** | Each data point reports the total since process start | Default for most SDKs; aggregation queries see monotonically increasing values |
| **Delta** | Each data point reports the change since last export | Tsuga aggregation works with both; delta is required for some Prometheus exporters |

Skills note: Tsuga aggregation (`tsuga aggregation scalar` / `tsuga aggregation timeseries`) handles temporality normalization. No skill action needed unless diagnosing missing data points.

---

## Naming Rules

All rules from https://opentelemetry.io/docs/specs/otel/metrics/supplementary-guidelines/#instrument-naming

1. **Dot notation, not underscores.** `http.server.request.duration`, not `http_server_request_duration`
2. **No service identity in metric name.** `web_backend_request_count` → BAD. Service identity belongs in the OTel resource attribute `service.name`, not the metric name. In Tsuga queries, filter by `context.service.name:<service>` (Tsuga's query field for service identity).
3. **No environment or version in metric name.** `prod_latency_ms`, `v2_errors` → BAD.
4. **No units in metric name.** `latency_ms`, `memory_bytes` → BAD. Units go in the instrument's `unit` metadata field.
5. **Verb-object pattern.** Prefer `{verb}.{object}` or `{namespace}.{object}.{verb}` — e.g., `http.server.request.duration`, `db.client.connections.usage`.
6. **Use OTel semantic conventions before custom names.** If a semconv namespace covers your signal, use it.

### Quick name check

Ask: Does the name contain any of these? → Flag it.

| Pattern | Rule violated | Fix |
|---|---|---|
| `_` (underscore) | Use dot notation | Replace `_` with `.` |
| Service name as prefix | No service identity in name | Remove; set `service.name` OTel resource attribute; filter via `context.service.name` in Tsuga queries |
| `_ms`, `_bytes`, `_count` suffix | No units in name | Remove suffix; set `unit` field |
| `prod_`, `staging_`, `v2_` prefix | No env/version in name | Remove; use resource attributes |

---

## Unit Validation

OTel requires a `unit` field on all non-dimensionless instruments. Units should follow UCUM notation where applicable.

| Unit | UCUM | Use for |
|---|---|---|
| `ms` | milliseconds | Latency, duration |
| `s` | seconds | Long durations |
| `By` | bytes | Memory, payload size |
| `1` | dimensionless | Ratios, fractions, percentages |
| `{request}` | annotated unit | Request counts (when distinguishing from raw numbers) |

**Rules:**
- Never encode units in the metric name — set the `unit` field instead
- Ratios and fractions use `1` (not `%`)
- If a semconv defines the unit, use it exactly

---

## Resource Attributes (Required for All Services)

Resource attributes identify the origin of telemetry and must be set at SDK initialization. They do NOT change per-operation.

| Attribute | Required | Example value |
|---|---|---|
| `service.name` | Yes | `web-backend` |
| `service.version` | Strongly recommended | `1.4.2` |
| `service.namespace` | Optional | `payments` |
| `telemetry.sdk.name` | Set by SDK | `opentelemetry` |
| `telemetry.sdk.version` | Set by SDK | `1.21.0` |
| `deployment.environment.name` | Strongly recommended | `production` |

> **Deprecated:** The older key `deployment.environment` (without `.name`) is deprecated as of OTel semconv 1.27.0. Use `deployment.environment.name` in new instrumentation.

**Common error:** Encoding service name or environment in metric/span names instead of using resource attributes. This makes queries brittle and prevents aggregation across versions.

---

## Span Status Codes

| Status | When to set | Notes |
|---|---|---|
| `UNSET` | Default; operation did not encounter an error | Most spans should remain UNSET |
| `OK` | Caller has validated success explicitly | Use sparingly; prefer UNSET for non-error |
| `ERROR` | The span represents a failed operation | Must set description with error detail |

**Common error:** Leaving `statusCode=UNSET` on spans that caught and handled exceptions. If an exception was thrown and the span represents a failed operation, set `ERROR`.

### Span Status Code Mapping by Kind

The correct status code depends on BOTH the status code value AND the span kind. This is the most common source of incorrect span status.

| Span Kind | HTTP 2xx | HTTP 4xx | HTTP 5xx |
|-----------|----------|----------|----------|
| SERVER | UNSET | **UNSET** (client's error, not server's) | ERROR |
| CLIENT | UNSET | **ERROR** (the call failed) | ERROR |

**Key rule:** A 400 Bad Request on a SERVER span is NOT an error. The server correctly processed the request and returned an appropriate response. Only set ERROR when the server itself failed (5xx).

### Span Kind Reference

| Kind | When to Use | Root span? |
|------|------------|-----------|
| SERVER | Inbound synchronous request (HTTP handler, gRPC handler) | Yes |
| CLIENT | Outbound synchronous call (HTTP client, DB query, gRPC client) | Never |
| PRODUCER | Async message send (Kafka publish, SQS send) | Never |
| CONSUMER | Async message receive/process | Yes (if no propagated context) |
| INTERNAL | Local logic with no network I/O | Never as root |

---

## Span Events vs Structured Logs

Span Events are still part of the OTel trace model. Use them where the spec requires, prefer structured logs where searchability matters.

- **Exception recording:** When an unhandled exception causes span status ERROR, record it as a span Event named `"exception"` with attributes `exception.type`, `exception.message`, `exception.stacktrace`. This is required by OTel exception semantics.
- **Other point-in-time occurrences:** Span Events are valid, but a structured log with `trace_id` + `span_id` injected is preferred — it is indexed for search in Tsuga and benefits from log-side enrichment and routing.

| Signal | Use case |
|---|---|
| Span event `"exception"` | Required when unhandled exception sets span status ERROR (OTel semconv) |
| Structured log with trace_id | Preferred for diagnostic events, business events, and state changes — searchable in Tsuga |

---

## Cross-Skill Pointers

| Topic | Skill |
|-------|-------|
| Signal type selection (metric vs span vs log) | `signal-choice-advisor` |
| Attribute naming (what key name to use) | `otel-semantic-conventions` |
| Collector processor ordering, YAML config | `otel-collector` |
| OTTL transformations and redaction | `otel-ottl` |
| Kubernetes pod spec with downward API | `otel-instrumentation` skill → `references/k8s-deployment.md` |
