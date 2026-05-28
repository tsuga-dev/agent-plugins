---
name: tsuga-right-size-metric-cardinality
description: "Use when a metric has too many unique attribute combinations, causing storage or performance issues."
tags: [metrics, cardinality, sdk, refactor, mutation]
---

# tsuga-right-size-metric-cardinality

Fix a high-cardinality metric attribute (e.g., `user_id`, `request_id` on a counter or gauge) by choosing the right signal — span attribute, log field, or SDK metric view — and applying the code change with explicit user confirmation.

> **Last verified:** 2026-03-21 | SDK versions: OTel Python 1.40.0, Go 1.31.0, Node.js 2.1.0, Java 2.25.0, .NET 1.9.0, Ruby 0.7.0, PHP 1.1.0, Rust opentelemetry 0.28.0, C++ 1.19.0

## When to Trigger

- "high cardinality metric" / "too many label values" / "metric cardinality explosion"
- "remove user_id from metric" / "reduce metric cost" / "metric is expensive"
- `tsuga-audit-metrics` output lists a dimension with cardinality > 1000 unique values
- Dashboard shows a metric fan-out (thousands of time series for one metric name)

## Workflow

### Step 1 — Identify the metric and offending attribute

Ask (or extract from `tsuga-audit-metrics` output):
- Metric name (e.g., `http_requests_total`)
- Offending attribute/label (e.g., `user_id`, `request_id`, `session_id`)
- Language/SDK in use

### Step 2 — Confirm cardinality via Tsuga

```
tsuga aggregation scalar --metric <metric_name> --groupBy <attribute_name> --aggregation count
```

If count > 1,000 unique values: confirmed high cardinality. Report the count.

### Step 3 — Determine the fix path

Present the three options and ask the user to choose (or recommend based on semantics):

| Option | When to use | What it does |
|--------|-------------|--------------|
| **A — Move to span attribute** | Value is per-request and trace-correlated | Remove from metric; add `span.set_attribute(key, value)` |
| **B — Move to log field** | Value needed for debugging only, not aggregation | Remove from metric; add structured log field |
| **C — SDK metric view (drop/aggregate)** | Must keep metric but reduce cardinality | Use SDK `View` to drop or bucket the attribute |

**Rule of thumb:**
- `user_id`, `request_id`, `session_id` → **Option A** (they belong on spans)
- Debugging-only values → **Option B**
- Business dimensions you want to keep but bucket (e.g., `plan_tier` with many values → group into `free/paid/enterprise`) → **Option C**

### Step 4 — Show proposed code change

Show the before/after code diff. Do **not** apply yet.

**Option A example (Python — move user_id from metric to span):**

Before:
```python
request_counter.add(1, {"user_id": user_id, "endpoint": endpoint})
```

After:
```python
span = trace.get_current_span()
span.set_attribute("user.id", user_id)
request_counter.add(1, {"endpoint": endpoint})  # user_id removed
```

**Option C — SDK metric view examples (drop attribute):**

*Python:*
```python
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.view import View

# Drop 'user_id' from http_requests_total
view = View(
    instrument_name="http_requests_total",
    attribute_keys={"endpoint", "method", "status_code"},  # user_id excluded
)
meter_provider = MeterProvider(views=[view], metric_readers=[reader])
```

*Go:*
```go
import "go.opentelemetry.io/otel/sdk/metric"

view := metric.NewView(
    metric.Instrument{Name: "http_requests_total"},
    metric.Stream{AttributeFilter: attribute.NewAllowKeysFilter("endpoint", "method", "status_code")},
    // user_id is not in the allow-list — it's dropped
)
mp := metric.NewMeterProvider(metric.WithView(view), metric.WithReader(reader))
```

*Node.js:*
```typescript
import { MeterProvider, View } from '@opentelemetry/sdk-metrics';

const meterProvider = new MeterProvider({
    views: [new View({
        instrumentName: 'http_requests_total',
        attributeKeys: ['endpoint', 'method', 'status_code'],
        // user_id not listed — dropped from all time series
    })],
    readers: [reader],
});
```

*Java:*
```java
SdkMeterProvider.builder()
    .registerView(
        InstrumentSelector.builder().setName("http_requests_total").build(),
        View.builder()
            .setAttributeFilter(Set.of("endpoint", "method", "status_code"))
            .build()  // user_id excluded
    )
    .registerMetricReader(reader)
    .build();
```

*.NET:*
```csharp
builder.Services.AddOpenTelemetry()
    .WithMetrics(metrics => metrics
        .AddView("http_requests_total",
            new MetricStreamConfiguration
            {
                TagKeys = new[] { "endpoint", "method", "status_code" }
                // user_id not listed — dropped
            }));
```

*Ruby (metric views not yet supported in SDK — use Option A or B):*
The Ruby OTel SDK does not yet support metric views. Use Option A (move to span attribute) or Option B (log field) for high-cardinality attributes in Ruby.

*PHP (metric views not yet supported in SDK — use Option A or B):*
The PHP OTel SDK does not yet support metric views. Use Option A (move to span attribute) or Option B (log field).

*Rust:*
```rust
use opentelemetry_sdk::metrics::{MeterProvider, View, Stream, Instrument};
use opentelemetry_sdk::metrics::reader::DefaultAggregationSelector;

let view = View::try_from(
    Instrument::builder().name("http_requests_total").build(),
    Stream::builder()
        .allowed_attribute_keys(vec!["endpoint", "method", "status_code"])
        .build(),
)?;
let mp = MeterProvider::builder()
    .with_view(view)
    .with_reader(reader)
    .build();
```

*C++:*
The C++ OTel SDK supports metric views via `opentelemetry::sdk::metrics::View`:
```cpp
#include <opentelemetry/sdk/metrics/view/view_registry.h>

auto view = std::make_shared<opentelemetry::sdk::metrics::View>(
    "http_requests_total",
    "Requests without high-cardinality user_id",
    "", // unit unchanged
    opentelemetry::sdk::metrics::AggregationType::kSum,
    std::shared_ptr<opentelemetry::sdk::metrics::AttributesProcessor>(
        new opentelemetry::sdk::metrics::FilteringAttributesProcessor(
            {"endpoint", "method", "status_code"}  // user_id excluded
        )
    )
);
```

### Step 5 — MUTATION GATE

### Confirm Before Applying

Before applying any code change (new file, edit, rename, dependency change):

1. Show the proposed change (diff, code block, or table) with a brief explanation of WHY
2. Wait for explicit user confirmation ("yes" / "no" / "select specific ones")
3. Apply only after confirmation

After deploy, recommend running `tsuga-smoke-test` to verify — do not block on it or treat it as a required step.

### Step 6 — Check downstream monitors and dashboards

Before removing the attribute from the metric, warn if any existing monitor or dashboard queries use it:

```
tsuga list-monitors --service <service-name>
tsuga list-dashboards
```

Search for the attribute name in monitor/dashboard definitions. If found:
- List the affected monitors/dashboards
- Warn: "These will break when the attribute is removed. Update them before or after the SDK change."

### Step 7 — Apply the code change

Apply the change from Step 4 (after user confirmation in Step 5).

### Step 8 — Verify with tsuga-audit-metrics

After deploying:
1. Wait for the next metric export cycle (default 60 seconds)
2. Re-run `tsuga-audit-metrics` on the same metric
3. Confirm the offending attribute is gone from the dimension list
4. Confirm time-series cardinality dropped

## Evidence Requirements

Before starting, collect:
- Metric name and offending attribute name
- Current cardinality count (from Tsuga or `tsuga-audit-metrics` output)
- Service name and language/SDK version
- Whether metric views are supported in the SDK (see Step 4 for per-language notes)

## Output Template

```
## Metric Cardinality Fix

**Metric:** `<metric_name>`
**Offending attribute:** `<attribute_name>`
**Confirmed cardinality:** <N> unique values

**Fix path chosen:** Option [A/B/C] — [description]

**Code change:**
[before/after snippet]

**Downstream impact:**
- Monitors affected: [list or "none found"]
- Dashboards affected: [list or "none found"]

**Verification:** Re-run `tsuga-audit-metrics` after deploy to confirm cardinality reduction.
```

## Safety Rules

- **MUTATION GATE:** Never apply code changes without explicit user confirmation ("yes").
- Never remove a metric attribute without first checking downstream monitors and dashboards.
- SDK metric views are preferred over removing the recording call entirely — they preserve the metric while reducing cardinality.
- Ruby and PHP SDKs do not support metric views — route to Option A or B for these languages.
- If the attribute has semantic meaning (e.g., `http.method`, `db.system`), do not remove it — it is not a cardinality problem by definition.

## Related Skills

- **`tsuga-audit-metrics`** — detects high-cardinality attributes (feeds this skill)
- **`tsuga-smoke-test`** — verifies the metric is still being exported after the fix
- **`signal-choice-advisor`** — helps decide whether a value belongs on metrics, spans, or logs
- **`tsuga-analyze-trace-latency`** — if the value was moved to a span attribute, use this to query it
