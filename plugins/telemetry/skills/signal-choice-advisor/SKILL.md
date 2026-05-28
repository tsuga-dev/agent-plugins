---
name: signal-choice-advisor
description: "Use whenever there's a question about signal type selection, instrument choice, or how to model a requirement in OTel — metric vs span vs log, counter vs histogram vs gauge. Trigger proactively if the user describes something they want to observe but hasn't decided how."
---

# Signal Choice Advisor

## Trigger

"Should this be a metric or a span?", "What signal do I use for X?", "Is this a counter or a histogram?", "Should I add a span event or a child span?", "How do I instrument X?", "What instrument type should I use?", "Should I log this or trace it?"

## Inputs

- **What the developer is trying to measure or observe** (required — ask if missing; a vague requirement produces a vague recommendation)
- **Service name** (optional; if provided, check what signals the service already emits)
- **Language/runtime** (optional; enables a concrete implementation sketch)

## Decision Framework

### Signal selection

| Signal | Use when | Do NOT use when |
|---|---|---|
| **Counter** | Counting discrete events that only increase (requests, errors, retries, cache misses) | Measuring duration — use Histogram or Span |
| **Histogram** | Measuring distributions (latency, payload size, queue wait time) | Debugging individual requests — use Spans |
| **UpDownCounter** | Current state of a resource that fluctuates (queue depth, active connections) | Tracking totals that never decrease — use Counter |
| **Observable Gauge** | Spot measurement sampled at collection time (CPU%, heap usage) | Per-request counting — use Counter or UpDownCounter |
| **Span** | An operation with significant duration you want to time, sample, and trace (a unit of work with a start and end) | A point-in-time occurrence — use a structured log instead |
| **Structured log (with trace_id)** | A timestamped occurrence within a request: exception detail, cache miss, state change, business event | Aggregate health measurements — use metrics |
| **Log field** | Rich per-request context: user agent, correlation IDs, business data, per-request identifiers | Aggregate health measurements — use metrics |
| **Resource attribute** | Identity that does not change per-operation: service name, version, environment, host | Per-request values — use span/log attributes |

### Key advisory rules

- **"Duration of X"** → strongly prefer **Span** (captures timing + causality; can derive histogram via aggregation). If already in traces, adding a duplicate Histogram metric may create redundancy.
- **"Count of X" where X is already a span** → prefer `span count` aggregation over a new Counter metric. Avoid counting what traces already measure.
- **"Count of X where X is a user / order / session"** → reject as a metric dimension (high cardinality). Use a log field or span attribute instead.
- **"Service name in metric name"** → always wrong. Set `service.name` as an OTel resource attribute; filter by `context.service.name` in Tsuga queries. Never encode service name in the metric name.
- **"Did Y happen inside operation Z"** → structured log with `trace_id` injected (NOT a child span); a structured log is preferred for Tsuga searchability; span events remain valid for exception recording per OTel spec.
- **"Span event vs child span"** → child spans are for operations with meaningful duration. For point-in-time occurrences, prefer a structured log with trace context for Tsuga searchability; span events remain valid for exception recording.
- **Before recommending a custom name** → check OTel semconv at https://opentelemetry.io/docs/specs/semconv/. Prefer a standard name before inventing a custom one.

## Workflow

1. Gather the requirement from the user. If the description is too vague (e.g., "instrument my service"), ask: "What specific operation or measurement are you trying to capture?"

2. If service name provided: `tsuga services list` → check `sources[]` to understand what signals the service already emits (logs only? both traces and logs?). This informs whether adding a metric would duplicate something already in traces.

3. Apply the decision framework above — explain the reasoning, not just the answer. State which alternatives were considered and why they were ruled out.

4. Check OTel semconv: does a standard convention already define this signal? Cite the relevant convention if applicable. Reference: https://opentelemetry.io/docs/specs/semconv/

5. If language is known: provide a concrete implementation sketch. For language API references: C++ · .NET · Go · Java · JS/Node.js · PHP · Python · Ruby · Rust — use the relevant `otel-<lang>` skill for a concrete implementation sketch.

## Output Template

```
## Signal Choice: <what is being measured>

## Recommendation: <Metric (Counter/Histogram/UpDownCounter/Gauge) / Span / Structured Log / Resource Attribute>

## Reasoning
- <Why this signal type fits the use case — be specific about the requirement>
- <Why alternatives do NOT fit — name the alternatives you considered>

## Semantic Convention Check
<Existing OTel semconv that applies — cite the attribute/metric name>
OR
<No matching convention found — custom name required; suggested name: <name> following OTel naming rules>

## Implementation Sketch (<language>)
<Concrete code example in the user's language, if known>

## Verification
After implementing, run `tsuga-smoke-test` for <service name> to confirm the signal arrives in Tsuga.

## Limitations
- This recommendation is advisory; specifics may differ based on auto-instrumentation already in place for your framework
- Cardinality of any custom metric attributes should be validated before shipping to production (rule: no per-request unique IDs as metric dimensions)
- If the service already emits traces, verify this metric does not duplicate signal that aggregation over spans can already provide
```

## Metric Cardinality Zones

Use this table to assess the risk of a proposed set of metric dimensions:

| Unique Time Series | Zone | Action |
|-------------------|------|--------|
| < 1,000 | Minimal | No action needed |
| 1,000 – 10,000 | Ideal | Healthy operating range |
| 10,000 – 50,000 | Acceptable | Monitor for growth; document expected ceiling |
| 50,000 – 100,000 | Caution | Investigate before adding more dimensions |
| 100,000 – 1,000,000 | Danger | Likely causing ingestion problems; investigate immediately |
| > 1,000,000 | Critical | Immediate action required; likely breaking ingestion |

**To estimate cardinality:** multiply the unique value counts of all dimensions.
Example: `http.route` (200 routes) × `http.response.status_code` (50 values) = 10,000 series — Ideal zone.
Example: `http.route` (200) × `user.id` (100,000 users) = 20,000,000 series — Critical.

## Cross-References

- **Attribute naming:** Before choosing a name for any metric dimension or span attribute, consult `otel-semantic-conventions` — a registry-first rule applies.
- **Collector-level processing:** Dimensions that should be dropped or normalized (e.g., removing `user.id` from metrics, redacting sensitive values) can be handled via `otel-collector` + `otel-ottl` in the pipeline. This is a safety net; prefer correct instrumentation at the source.
- **"Should this be in app code or Collector?"**
  - Set resource attributes (service.name, k8s metadata) → app code or env vars (not Collector)
  - Drop noisy spans (health checks) → Collector filter processor
  - Redact sensitive attribute values → Collector transform processor (OTTL)
  - Add derived metrics from spans → Collector `spanmetrics` or `signaltometrics` connector
  - Sampling decisions → Collector tail sampling (or SDK head sampling for simple cases)

## Related Skills / Next Steps
- `otel-instrumentation` — full SDK setup for a new service
- `otel-<lang>` — language-specific implementation of the recommended signal
- `tsuga-audit-metrics` — audit existing metrics for design issues
- `otel-instrumentation` — cross-signal audit (routes to per-lang `references/audit-checklist.md`)

## Safety Rules

- Never recommend metrics with per-request unique identifiers as dimensions (`user_id`, `order_id`, `session_id`, `request_id` = always high-cardinality)
- If unsure about cardinality: state it explicitly as a risk in the Limitations section
- Never claim a recommendation is definitively "correct" without stating what assumption it relies on
- If OTel semconv defines a standard name: always prefer it over a custom name
- Advisory output only — this skill does not write code changes
