# OTel Reference

Canonical reference for OpenTelemetry instrument types, naming rules, and telemetry best practices. Cross-language reference used by routing and advisory skills.

> For authoritative rules: https://opentelemetry.io/docs/specs/otel/metrics/supplementary-guidelines/ and https://opentelemetry.io/docs/specs/semconv/

---

## Instrument Types

| Instrument | Use case | Monotonic? | Example |
|---|---|---|---|
| **Counter** | Counts discrete events that only increase | Yes | `db.client.operation.count`, `db.client.errors` |
| **UpDownCounter** | Fluctuating current values | No | `db.client.connections.usage`, `messaging.client.consumed.messages` |
| **Histogram** | Distributions of values (latency, size) | No | `http.server.request.duration`, `http.server.request.body.size` |
| **Observable Counter** | Monotonically increasing total, sampled at collection | Yes | Total bytes sent (read from system counter) |
| **Observable UpDownCounter** | Fluctuating total, sampled at collection | No | Active thread count, heap memory usage |
| **Observable Gauge** | Spot measurement at collection time | No | CPU utilization (%), current queue depth |

> Unsure which type fits? → `signal-choice-advisor`

---

## Language API References

| Language | Instrument API | Full API Reference |
|---|---|---|
| C++ | `meter->CreateDoubleCounter(name)` · `CreateDoubleHistogram(name)` · `CreateDoubleUpDownCounter(name)` · `CreateDoubleObservableGauge(name)` | [opentelemetry-cpp.readthedocs.io](https://opentelemetry-cpp.readthedocs.io/en/latest/) |
| .NET | `myMeter.CreateCounter<T>(name)` · `CreateHistogram<T>(name)` · `CreateUpDownCounter<T>(name)` · `CreateObservableGauge<T>(name, observeValue)` | [System.Diagnostics.Metrics](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.metrics) |
| Go | `meter.Int64Counter(name)` · `meter.Float64Histogram(name)` · `meter.Int64UpDownCounter(name)` · `meter.Float64ObservableGauge(name, cb)` | [pkg.go.dev/go.opentelemetry.io/otel](https://pkg.go.dev/go.opentelemetry.io/otel) |
| Java | `meter.counterBuilder(name).build()` · `histogramBuilder(name).build()` · `upDownCounterBuilder(name).build()` · `gaugeBuilder(name).buildWithCallback(cb)` | [javadoc.io/doc/io.opentelemetry](https://javadoc.io/doc/io.opentelemetry) |
| JavaScript / Node.js | `meter.createCounter(name)` · `createHistogram(name)` · `createUpDownCounter(name)` · `createObservableGauge(name)` | [open-telemetry.github.io/opentelemetry-js](https://open-telemetry.github.io/opentelemetry-js/) |
| PHP | `$meter->createCounter($name)` · `createHistogram($name)` · `createUpDownCounter($name)` · `createObservableGauge($name)` | [open-telemetry.github.io/opentelemetry-php](https://open-telemetry.github.io/opentelemetry-php/) |
| Python | `meter.create_counter(name)` · `create_histogram(name)` · `create_up_down_counter(name)` · `create_observable_gauge(name, callbacks=[cb])` | [opentelemetry-python.readthedocs.io](https://opentelemetry-python.readthedocs.io/en/latest/) |
| Ruby | `meter.create_counter(name)` · `create_histogram(name)` · `create_up_down_counter(name)` · `create_observable_gauge(name, &cb)` | [rubydoc.info/gems/opentelemetry-sdk](https://www.rubydoc.info/gems/opentelemetry-sdk) |
| Rust | `meter.u64_counter(name).build()` · `f64_histogram(name).build()` · `i64_up_down_counter(name).build()` · `f64_observable_gauge(name).build()` | [docs.rs/opentelemetry](https://docs.rs/opentelemetry/latest/opentelemetry/) |

> For language-specific caveats, SDK support notes, and full environment variable reference, see `otel-<lang>/references/otel-reference.md`.

---

## Temporality

| Mode | Meaning | Tsuga behavior |
|---|---|---|
| **Cumulative** | Each data point reports the total since process start | Default for most SDKs; aggregation queries see monotonically increasing values |
| **Delta** | Each data point reports the change since last export | Tsuga aggregation works with both; delta is required for some Prometheus exporters |

Skills note: Tsuga aggregation (`tsuga aggregation scalar` / `tsuga aggregation timeseries`) handles temporality normalization. No skill action needed unless diagnosing missing data points.

---

## Naming Rules

All rules from https://opentelemetry.io/docs/specs/semconv/general/naming/

1. **Dots for namespace hierarchy, underscores for snake_case within components.** `http.server.request.duration`, not `http_server_request_duration`. Multi-word components use underscores: `http.response.status_code`, `process.command_args`.
2. **No service identity in metric name.** `web_backend_request_count` → BAD. Service identity belongs in the OTel resource attribute `service.name`, not the metric name. In Tsuga queries, filter by `context.service.name:<service>` (Tsuga's query field for service identity).
3. **No environment or version in metric name.** `prod_latency_ms`, `v2_errors` → BAD.
4. **No units in metric name.** `latency_ms`, `memory_bytes` → BAD. Units go in the instrument's `unit` metadata field.
5. **Verb-object pattern.** Prefer `{verb}.{object}` or `{namespace}.{object}.{verb}` — e.g., `http.server.request.duration`, `db.client.connections.usage`.
6. **Use OTel semantic conventions before custom names.** If a semconv namespace covers your signal, use it.

### Quick name check

Ask: Does the name contain any of these? → Flag it.

| Pattern | Rule violated | Fix |
|---|---|---|
| `_` used as namespace separator (e.g., `http_server_request`) | Use dots for namespace hierarchy | Replace `_` between namespaces with `.`; keep `_` for snake_case within components (e.g., `status_code`) |
| Service name as prefix | No service identity in name | Remove; set `service.name` OTel resource attribute; filter via `context.service.name` in Tsuga queries |
| `_ms`, `_bytes`, `_count` suffix | No units in name | Remove suffix; set `unit` field |
| `prod_`, `staging_`, `v2_` prefix | No env/version in name | Remove; use resource attributes |

---

## Unit Validation

OTel requires a `unit` field on all non-dimensionless instruments. Units should follow UCUM notation where applicable.

| Unit | UCUM | Use for |
|---|---|---|
| `ms` | milliseconds | Fine-grained latency (non-semconv) |
| `s` | seconds | Duration, latency (semconv default — e.g., `http.server.request.duration`) |
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
| `service.namespace` | Required (Stable) | `payments` |
| `telemetry.sdk.name` | Set by SDK | `opentelemetry` |
| `telemetry.sdk.version` | Set by SDK | `1.21.0` |
| `deployment.environment.name` | Strongly recommended | `production` |

> **Deprecated:** The older key `deployment.environment` (without `.name`) is deprecated as of OTel semconv v1.27.0. Use `deployment.environment.name` in new instrumentation.

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
| Language-specific env vars and SDK caveats | `otel-<lang>/references/otel-reference.md` |
