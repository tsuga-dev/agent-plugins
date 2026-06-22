# Signal Choice Reference

Decision matrix for choosing between metrics, spans, logs, and resource attributes. Used by instrumentation quality skills.

> Note: For point-in-time diagnostic occurrences, structured logs with trace context are preferred over span events in Tsuga — they are searchable and benefit from log routing. Exception events on spans remain required per OTel spec.

---

## Decision Matrix

| What you want to observe | Signal | Why |
|---|---|---|
| Count of discrete events (requests, errors, retries) | **Counter metric** | Aggregatable over time; queryable as rate or total |
| Distribution of an operation's duration or size | **Histogram metric** | Enables p50/p95/p99; cannot be done with counter |
| Current state of a resource (queue depth, open connections) | **UpDownCounter or Observable Gauge** | State fluctuates; counter is monotonic-only |
| An operation with duration you want to time, trace, and sample | **Span** | Captures timing, parent/child causality, sampling decisions |
| A point-in-time occurrence within an ongoing request (exception detail, cache miss, state change, business event) | **Structured log with trace_id** | Preferred for searchability in Tsuga; span events remain valid for exception recording per OTel spec |
| Rich context attached to a specific request or event | **Span attribute or log field** | Per-request data; not for aggregation |
| Identity that does not change per-operation (service name, version, environment, host) | **Resource attribute** | Set once at SDK init; appears on all signals from this instance |

---

## Anti-Pattern Registry

These are the most common instrumentation mistakes and why they are wrong.

### "Duration counter" anti-pattern

**Looks like:** A counter named `request_time_total` or `operation_duration_count` that increments by the duration in milliseconds each call.

**Why wrong:** Counters cannot express distributions or percentiles. You can get "total time spent" but not "what was the p95 latency?" A Histogram is required for latency analysis.

**Fix:** Use a Histogram instrument. The SDK automatically tracks count, sum, and bucket distribution.

---

### "Service name in metric name" anti-pattern

**Looks like:** `web_backend_http_requests_total`, `payments_service_errors`

**Why wrong:** Service identity belongs in the `service.name` resource attribute. Encoding it in the metric name makes all queries service-specific, prevents aggregation across a fleet, and creates naming drift when services are renamed.

**Fix:** Use `http.server.request.duration` (or the appropriate semconv name) and filter by `context.service.name:web-backend` in queries.

---

### "High-cardinality metric dimension" anti-pattern

**Looks like:** A metric with a `user_id`, `order_id`, `session_id`, `request_id`, or `trace_id` attribute/label.

**Why wrong:** Every unique value creates a new time series. A service handling 1M unique users creates 1M metric time series — this causes cardinality explosions, high storage costs, and query timeouts.

**Fix:**
- Per-request identifiers → **span attribute** or **log field** (not metric dimension)
- If you need to count distinct users/orders → use a **log field** plus a bounded log analytics query, not a raw metric dimension

---

### "Child span for a point-in-time event" anti-pattern

**Looks like:** A child span with duration < 1ms, used to record "cache miss occurred" or "user not found."

**Why wrong:** Spans are for operations with meaningful duration that benefit from sampling and trace visualization. A point-in-time occurrence adds noise to the trace waterfall and provides no timing value.

**Fix:** Emit a structured log record with `trace_id` and `span_id` injected. This records the event, links it to the trace, and appears in Tsuga log correlation — without polluting the span tree.

---

### "Span event vs structured log for diagnostic detail" anti-pattern

**Looks like:** `span.addEvent("cache.miss", { "cache.key": "..." })` — using a span event for a diagnostic occurrence when a structured log would be more searchable.

**Why it matters:** Span events are valid OTel constructs, but they are not indexed for log search in Tsuga and do not benefit from log-side enrichment or routing. For diagnostic events you want to query independently, a structured log with `trace_id` + `span_id` is better.

**Exception case:** `span.addEvent("exception", { "exception.type": "...", "exception.message": "...", "exception.stacktrace": "..." })` when the span also sets status ERROR is *correct* per OTel exception semantics — keep it. You may *also* emit a structured log for Tsuga searchability, but the span event itself is not wrong.

**Fix for non-exception span events:** Emit a structured log record with `trace_id` and `span_id` fields instead. This records the event, links it to the trace, and is indexed for search in Tsuga.

---

### "Environment in metric name" anti-pattern

**Looks like:** `prod_http_requests`, `staging_error_count`, `v2_latency_ms`

**Why wrong:** Environment and version identity belongs in resource attributes (`deployment.environment.name`, `service.version`). Encoding them in names creates duplicate metric definitions per environment, breaks dashboards on promotion, and prevents cross-environment comparison in a single query.

**Fix:** Use a single metric name and filter by `deployment.environment.name:production` in queries.

---

### "Units in metric name" anti-pattern

**Looks like:** `request_latency_ms`, `memory_usage_bytes`, `cache_hit_rate_pct`

**Why wrong:** Units are a metadata field on the instrument, not part of the name. Including them in the name causes confusion if units change (ms → seconds) and violates OTel naming conventions.

**Fix:** Set the `unit` field on the instrument (e.g., `ms`, `By`, `1` for ratios). Use a clean name like `http.server.request.duration` with `unit: ms`.

---

## Cardinality Rules

| Attribute type | OK as metric dimension? | OK as span attribute? | OK as log field? |
|---|---|---|---|
| Static identity (env, region, version) | Yes | Yes | Yes |
| Low-cardinality category (HTTP method, status code, tier) | Yes | Yes | Yes |
| Medium-cardinality identity (endpoint path without IDs) | Yes (with care) | Yes | Yes |
| High-cardinality identity (user ID, order ID, session ID) | **No** | Yes | Yes |
| Unique per-request (request ID, trace ID) | **No** | Yes (trace_id) | Yes (trace_id) |

**Rule of thumb:** If the value could be a unique string for each request, it is not a metric dimension.

---

## Correlation Requirements

For logs and traces to be linked in Tsuga:

1. **`trace_id` field** must be present in log records (as a top-level field, not embedded in the message string)
2. **`span_id` field** should also be present (links log to the exact span)
3. **`trace_flags` field** is recommended for non-OTLP JSON log formats per OTel's "Trace Context in non-OTLP Log Formats" spec
4. Both `trace_id` and `span_id` must use the W3C TraceContext format (lowercase hex, no dashes for trace_id)
5. The log must be emitted while the span is active (so the SDK can inject context automatically)

If a service emits both logs and traces but logs are missing `trace_id`: this is the most impactful single instrumentation fix — it unlocks trace-to-log navigation in Tsuga.

---

## What Belongs Where

```
Resource attributes  ← service.name, service.version, deployment.environment.name, host.name
     ↓ (set once at SDK init; appear on every signal)

Span attributes      ← http.request.method, http.response.status_code, db.operation.name,
                       order.id (per-request, not a metric dimension)

Log fields           ← trace_id, span_id (correlation keys),
                       exception details, business event data, user context

Metric dimensions    ← http.response.status_code, http.request.method, deployment.environment.name
                       (low-cardinality only; aggregate values, not individual identifiers)
```
