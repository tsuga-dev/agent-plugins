# OTel Reference — Go

Canonical reference for OpenTelemetry instrument types, naming rules, and telemetry best practices. Go-specific SDK API and environment variable details.

> For authoritative rules: https://opentelemetry.io/docs/specs/otel/metrics/supplementary-guidelines/ and https://opentelemetry.io/docs/specs/semconv/

---

## Instrument Types

| Instrument | Use case | Monotonic? | Example |
|---|---|---|---|
| **Counter** | Counts discrete events that only increase | Yes | `http.server.request.count`, `db.client.errors` |
| **UpDownCounter** | Fluctuating current values | No | `db.client.connections.usage`, `messaging.client.consumed.messages` |
| **Histogram** | Distributions of values (latency, size) | No | `http.server.request.duration`, `http.server.request.body.size` |
| **Observable Counter** | Monotonically increasing total, sampled at collection | Yes | Total bytes sent (read from system counter) |
| **Observable UpDownCounter** | Fluctuating total, sampled at collection | No | Active thread count, heap memory usage |
| **Observable Gauge** | Spot measurement at collection time | No | CPU utilization (%), current queue depth |

> Unsure which type fits? → `signal-choice-advisor`

---

## Go Instrument API

| Instrument | SDK Method | Notes |
|---|---|---|
| Counter (int64) | `meter.Int64Counter(name, metric.WithUnit(...), metric.WithDescription(...))` | Returns `(instrument.Int64Counter, error)` |
| Counter (float64) | `meter.Float64Counter(name, ...)` | Use for decimal values |
| Histogram (float64) | `meter.Float64Histogram(name, ...)` | Common for latency/duration |
| Histogram (int64) | `meter.Int64Histogram(name, ...)` | Integer variant |
| UpDownCounter (int64) | `meter.Int64UpDownCounter(name, ...)` | Supports negative delta |
| Gauge (int64) | `meter.Int64Gauge(name, ...)` | Synchronous gauge — records a spot measurement inline (stable since SDK v1.23); use when you have the value at call time; use ObservableGauge when polling periodically |
| Gauge (float64) | `meter.Float64Gauge(name, ...)` | Float64 synchronous gauge variant |
| Observable Gauge (float64) | `meter.Float64ObservableGauge(name, metric.WithFloat64Callback(cb))` | `cb` is called by `PeriodicReader` on each export cycle — do not block or make network calls inside it |
| Observable Counter (float64) | `meter.Float64ObservableCounter(name, metric.WithFloat64Callback(cb))` | — |
| Observable UpDownCounter (float64) | `meter.Float64ObservableUpDownCounter(name, metric.WithFloat64Callback(cb))` | — |

**Recording values:**
```go
counter.Add(ctx, 1, metric.WithAttributes(attribute.String("method", "GET")))
histogram.Record(ctx, 42.5, metric.WithAttributes(attribute.String("endpoint", "/api")))
```

> **Cardinality warning:** Do not use `userId`, `requestId`, or any per-request string in `metric.WithAttributes(...)`. Use low-cardinality values only.

---

## Environment Variables Reference

> **SDK auto-reads:** `otlptracehttp.New(ctx)` / `otlptracegrpc.New(ctx)` with NO options auto-reads `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_HEADERS`, `OTEL_EXPORTER_OTLP_TIMEOUT`, `OTEL_EXPORTER_OTLP_COMPRESSION`. `resource.WithFromEnv()` reads `OTEL_SERVICE_NAME` and `OTEL_RESOURCE_ATTRIBUTES`. `OTEL_TRACES_EXPORTER` / `OTEL_METRICS_EXPORTER` are NOT auto-read — Go SDK must be initialized in code.

| Variable | Purpose | Required? | Default (per spec) | SDK auto-reads? | Go notes |
|---|---|---|---|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP endpoint URL | **yes** | `http://localhost:4318` | yes | Zero-arg `otlptracehttp.New(ctx)` reads this |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | Transport protocol | no | `http/protobuf` | partial | Protocol is set by which package you import (`otlptracehttp` vs `otlptracegrpc`) |
| `OTEL_EXPORTER_OTLP_HEADERS` | Auth/custom headers | depends | (none) | yes | — |
| `OTEL_EXPORTER_OTLP_TIMEOUT` | Export timeout (ms) | no | `10000` | yes | — |
| `OTEL_EXPORTER_OTLP_COMPRESSION` | Compression | no | `none` | yes | `gzip` recommended for production |
| `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | Traces-only endpoint | no | inherits `OTEL_EXPORTER_OTLP_ENDPOINT` | yes | — |
| `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT` | Metrics-only endpoint | no | inherits `OTEL_EXPORTER_OTLP_ENDPOINT` | yes | — |
| `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` | Logs-only endpoint | no | inherits `OTEL_EXPORTER_OTLP_ENDPOINT` | yes | — |
| `OTEL_TRACES_EXPORTER` | Traces exporter type | no | `otlp` | **no** | Go has no agent; SDK must be init'd in code |
| `OTEL_METRICS_EXPORTER` | Metrics exporter type | no | `otlp` | **no** | Go has no agent; SDK must be init'd in code |
| `OTEL_LOGS_EXPORTER` | Logs exporter type | no | `otlp` | **no** | Go log bridge is experimental (v0.x) |
| `OTEL_SERVICE_NAME` | Service name | **yes** | (none) | yes | via `resource.WithFromEnv()` |
| `OTEL_RESOURCE_ATTRIBUTES` | Additional resource attrs | no | (none) | yes | via `resource.WithFromEnv()` |
| `OTEL_SDK_DISABLED` | Disable SDK (noop) | no | `false` | partial | — |
| `OTEL_TRACES_SAMPLER` | Sampler type | no | `parentbased_always_on` | yes | — |
| `OTEL_TRACES_SAMPLER_ARG` | Sampler argument | no | (sampler-specific) | yes | Required when sampler is `traceidratio` |
| `OTEL_PROPAGATORS` | Context propagators | no | `tracecontext,baggage` | **no** | Core SDK does not auto-read; use `autoprop.NewTextMapPropagator()` from `go.opentelemetry.io/contrib/propagators/autoprop` to enable env-driven propagator selection |
| `OTEL_BSP_SCHEDULE_DELAY` | BSP export interval (ms) | no | `5000` | yes | — |
| `OTEL_BSP_MAX_QUEUE_SIZE` | BSP max queue | no | `2048` | yes | — |
| `OTEL_BSP_MAX_EXPORT_BATCH_SIZE` | BSP max batch | no | `512` | yes | — |

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
