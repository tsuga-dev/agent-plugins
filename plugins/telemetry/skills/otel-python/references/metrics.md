# Metrics — Python OTel SDK

> **Last verified:** 2026-03-23 | SDK: `opentelemetry-sdk` 1.40.0

---

## Instrument Selection

| What you're measuring | Instrument | Python method |
|-----------------------|-----------|---------------|
| Events that only increase (requests, errors) | Counter | `meter.create_counter` |
| Values that go up and down (queue depth, active connections) | UpDownCounter | `meter.create_up_down_counter` |
| Distribution of values (latency, payload size) | Histogram | `meter.create_histogram` |
| Spot value available inline at record time | **Gauge** (synchronous) | `meter.create_gauge` |
| Polled value (CPU %, memory) | Observable Gauge | `meter.create_observable_gauge` |
| Monotonically increasing total, polled | Observable Counter | `meter.create_observable_counter` |
| Fluctuating total, polled | Observable UpDownCounter | `meter.create_observable_up_down_counter` |

> Unsure which fits? → `signal-choice-advisor`

---

## All Instruments with Python API

### Counter

```python
from opentelemetry import metrics

meter = metrics.get_meter("my-service")

request_counter = meter.create_counter(
    "http.server.request.count",
    unit="{request}",
    description="Total number of HTTP requests",
)

# Record — always positive delta
request_counter.add(1, {"http.method": "GET", "http.status_code": "200"})
```

### UpDownCounter

```python
active_connections = meter.create_up_down_counter(
    "db.client.connections.usage",
    unit="{connection}",
    description="Number of active database connections",
)

active_connections.add(1, {"pool": "primary"})   # connection acquired
active_connections.add(-1, {"pool": "primary"})  # connection released
```

### Histogram

```python
request_duration = meter.create_histogram(
    "http.server.request.duration",
    unit="ms",
    description="HTTP request duration",
)

request_duration.record(42.5, {"http.method": "GET", "http.route": "/users/{id}"})
```

### Gauge (synchronous) — stable since SDK 1.23

Use when the value is available inline at call time (not polled on a schedule).

```python
# BAD — using an observable gauge callback just to read an in-memory variable
def cache_size_callback(options):
    return [(len(cache), {})]
meter.create_observable_gauge("cache.entries", callbacks=[cache_size_callback])

# GOOD — record inline when the value changes
cache_size_gauge = meter.create_gauge(
    "cache.entries",
    unit="{entry}",
    description="Current number of entries in the cache",
)

def add_to_cache(key, value):
    cache[key] = value
    cache_size_gauge.set(len(cache), {"cache": "user-sessions"})
```

### Observable Gauge (polled)

Use for values polled by the SDK at export time (CPU %, memory).

```python
import psutil

def cpu_utilization_callback(options):
    # Called once per export interval by PeriodicExportingMetricReader
    # Must not block or perform I/O that could delay export
    yield metrics.Observation(psutil.cpu_percent() / 100, {"core": "all"})

meter.create_observable_gauge(
    "system.cpu.utilization",
    callbacks=[cpu_utilization_callback],
    unit="1",
    description="CPU utilization ratio",
)
```

**Observable callback rules:**
- Callback is invoked by `PeriodicExportingMetricReader` on the export schedule — do NOT block, sleep, or perform slow I/O
- Return an iterable of `metrics.Observation(value, attributes_dict)` objects (or yield them)
- The `options` parameter (`CallbackOptions`) is unused in most cases; it carries a timeout hint

### Observable Counter

```python
def bytes_sent_callback(options):
    yield metrics.Observation(get_total_bytes_sent(), {"interface": "eth0"})

meter.create_observable_counter(
    "system.network.io",
    callbacks=[bytes_sent_callback],
    unit="By",
)
```

### Observable UpDownCounter

```python
def thread_count_callback(options):
    import threading
    yield metrics.Observation(threading.active_count(), {})

meter.create_observable_up_down_counter(
    "process.runtime.cpython.thread_count",
    callbacks=[thread_count_callback],
    unit="{thread}",
)
```

### Batching multiple observations in one callback

```python
def per_core_cpu_callback(options):
    for i, pct in enumerate(psutil.cpu_percent(percpu=True)):
        yield metrics.Observation(pct / 100, {"cpu.core": str(i)})

meter.create_observable_gauge(
    "system.cpu.utilization",
    callbacks=[per_core_cpu_callback],
    unit="1",
)
```

---

## Cardinality Warning

Every unique attribute combination creates a separate time series. High cardinality destroys query performance and costs money.

```python
# BAD — user_id has millions of values
request_counter.add(1, {"user_id": user.id, "endpoint": "/api/orders"})

# GOOD — bucket status codes, use semconv attribute names
status_bucket = str(response.status_code // 100) + "xx"  # "2xx", "4xx", "5xx"
request_counter.add(1, {"http.method": "GET", "http.response.status_code": status_bucket})
```

Never use as metric attributes:
- User IDs, session tokens, request IDs
- Full URLs, raw paths, query strings
- Timestamps, hostnames with high turnover
- Any runtime-generated string

---

## `OTEL_METRICS_EXPORTER` Python SDK Caveat

The spec default for `OTEL_METRICS_EXPORTER` is `otlp`, but the Python SDK currently treats an unset value as `none` — metrics are silently not exported if unset.

```bash
# Auto-instrumentation CLI: set the env var explicitly
OTEL_METRICS_EXPORTER=otlp
# Manual SDK init: configure MeterProvider with a reader (env var is not honored)
```

With manual SDK init, the `MeterProvider` must be initialized with a `PeriodicExportingMetricReader` — the env var alone is not enough. See `references/quickstart.md`.

---

## Verification

```bash
tsuga metrics list --filter "service.name=my-service"
# Expected: instruments appear within one export interval (default 60s)

# Speed up for testing
reader = PeriodicExportingMetricReader(OTLPMetricExporter(), export_interval_millis=5000)
```
