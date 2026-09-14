---
name: signal-choice-advisor
description: "Use whenever there is a question about telemetry modeling: which OTel signal to emit (metric vs span vs structured log vs resource attribute), which instrument to pick (Counter, Histogram, UpDownCounter, Observable Gauge), what to name it against the semantic conventions, where an attribute belongs (resource vs span vs span event vs log record vs metric datapoint), and whether a proposed metric dimension is low-cardinality enough to ship. Trigger proactively when someone describes something they want to observe but has not decided how to instrument it. Advisory only; route the SDK implementation to otel-instrumentation."
---

Help the user choose between metric / span / structured log / resource attribute, and between Counter / Histogram / UpDownCounter / Gauge. Advisory by default: this skill decides the signal, the name, and the placement, and never writes the code.

## Inputs

- What the developer is trying to measure or observe (required - ask if missing; a vague requirement produces a vague recommendation).
- Service name (optional - if provided, use `tsuga services list` to see whether the service already emits traces).
- Language/runtime (optional - enables a concrete implementation sketch).

## Documentation grounding

Use `tsuga docs search`, then `tsuga docs get`, for product and API details. Cite `path`, `title`, and `link` when docs were used. Fetch these when naming, modeling, or explaining the Tsuga mapping:

| Need                  | Page                                                            |
| --------------------- | --------------------------------------------------------------- |
| Resource attributes   | `data-collection/guides/how-to-add-resource-attributes`         |
| OTel to Tsuga mapping | `data-collection/guides/default-mapping-for-opentelemetry-formats` |
| Signal choice         | `data-collection/guides/how-to-choose-a-telemetry-signal`       |
| Common anti-patterns  | `references/telemetry/signal-choice`                            |

Tsuga docs first. If they do not settle a naming decision, check the OpenTelemetry semantic conventions at https://opentelemetry.io/docs/specs/semconv/ before inventing a name. If neither covers the recommendation, label it `Recommendation (not verified in Tsuga or OTel docs)`.

## Signal selection

| Signal                            | Use when                                                                                            | Do NOT use when                           |
| --------------------------------- | --------------------------------------------------------------------------------------------------- | ----------------------------------------- |
| Counter                           | Counting discrete events that only increase: requests, errors, retries, cache misses                | Measuring duration; use Histogram or Span |
| Histogram                         | Measuring distributions: latency, payload size, queue wait time                                     | Debugging individual requests; use Spans  |
| UpDownCounter                     | Current state that fluctuates: queue depth, active connections                                      | Tracking totals that never decrease       |
| Observable Gauge                  | Spot measurement sampled at collection time: CPU%, heap usage                                       | Per-request counting                      |
| Span                              | An operation with meaningful duration, causality, and sampling value                                | A point-in-time occurrence                |
| Structured log with trace context | Timestamped occurrence inside a request: exception detail, cache miss, state change, business event | Aggregate health measurements             |
| Resource attribute                | Identity that does not change per operation: service, version, environment, host                    | Per-request values                        |

Key rules:

- "Duration of X" → prefer a Span when X is already an operation; a Histogram only when the aggregate distribution is what matters. Adding a Histogram on top of existing traces is often redundant.
- "Count of X where X is already a span" → aggregate the span count; do not add a duplicate Counter.
- "Count of X where X is a user / order / session" → reject as a metric dimension (unbounded). Use a log field or span attribute.
- "Did Y happen inside operation Z" → a structured log carrying `trace_id` / `span_id`, NOT a child span. Span events remain the right place for exception recording.
- Child spans are for operations with meaningful duration, never "thing happened" markers.

## Naming and placement

- Check Tsuga docs, then the official OTel conventions, before inventing any span, metric, log, or resource attribute name. Use the standard name even when the convention is still Development status.
- Set resource attributes once for the process, never per span.
- Use `deployment.environment.name`, not the deprecated `deployment.environment`.
- Use `http.route`, never raw `url.path`, as an HTTP metric dimension.
- "Service name in the metric name" is always wrong: set `service.name` as a resource attribute and filter by `context.service.name` in queries. The same goes for environment, version, and units.

| Belongs on       | Use for                                                                                                                  |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Resource         | `service.name`, `service.version`, `service.instance.id`, `deployment.environment.name`, `k8s.pod.uid`, `host.name`      |
| Span             | Request-specific fields such as `http.request.method`, `http.response.status_code`, `db.operation.name`, `db.query.text` |
| Span event       | Exceptions: `exception.type`, `exception.message`, `exception.stacktrace`                                                |
| Log record       | Per-log fields plus the `trace_id` and `span_id` correlation fields                                                      |
| Metric datapoint | Low-cardinality dimensions such as `http.route`, status code, method, or `db.system.name`                                |

## Cardinality guardrail

Estimate the series count by multiplying the unique values across every dimension before recommending it. If a dimension can grow with users, orders, sessions, request IDs, raw URLs, query strings, or trace IDs, reject it as a metric dimension and put it on a span or log instead. These zones are heuristics; cite real evidence when making a verified finding, and use `tsuga docs search` / `tsuga docs get` for current Tsuga limits.

| Unique time series | Zone       | Action                                    |
| ------------------ | ---------- | ----------------------------------------- |
| < 1,000            | Minimal    | OK                                        |
| 1,000-10,000       | Ideal      | Healthy                                   |
| 10,000-50,000      | Acceptable | Monitor growth                            |
| 50,000-100,000     | Caution    | Investigate before adding more dimensions |
| 100,000-1,000,000  | Danger     | Likely ingestion or query risk            |
| > 1,000,000        | Critical   | Do not ship without redesign              |

## Workflow

1. Gather the requirement. If it is too vague, ask: "What specific operation, event, or measurement are you trying to capture?"
2. If a service name was given: `tsuga services list` → check `traceRequestRate` to see whether the service already emits traces. Absent is not the same as 0; absent means the query failed.
3. For an existing metric's shape or cardinality, read its metadata with `tsuga metrics get` over an explicit window and cite the command and value you used.
4. Apply signal choice, naming, placement, and cardinality. Explain the reasoning, not just the answer, and name the alternatives you rejected.
5. If code or live telemetry was inspected, share preliminary observations and ask whether they match the user's understanding of how the service instruments itself.
6. For the SDK implementation, hand off rather than generating code here.

## Verification

After implementing, confirm the signal arrives: `tsuga traces search` or `tsuga logs search` for a new span or log, `tsuga metrics get` plus `tsuga aggregation scalar` for a new metric.

## Output

```markdown
## Recommendation

## Evidence Used

## Reasoning

## Semantic Convention Check

## Cardinality

## Understanding Check (omit if no code or telemetry evidence was inspected)

## Verification

## Limitations
```

Label every finding `source: code analysis` or `source: tsuga CLI`, and a verified one as
`Finding (source: tsuga CLI, command: <command>, value: <value>)`.

## Related skills

- `otel-instrumentation` - SDK implementation, once the signal and naming decision is made
- `otel-collector` - collector transforms, filters, routing, redaction, and OTTL
- `tsuga-audit-telemetry-quality` - audit existing metric design and broader telemetry quality
- `tsuga-debug-telemetry-ingestion` - verify the signal arrives after implementation

## Safety

- Never recommend a metric dimension carrying per-request unique identifiers (`user_id`, `order_id`, `session_id`, `request_id`).
- If unsure about cardinality, state it as a risk rather than guessing.
- If OTel semconv defines a standard name, always prefer it.
- Advisory output only. If you propose a source change, show it and require explicit confirmation before any edit.
- Never read `.env`, `*.secret`, `*credentials*`, or `*token*` files, and never reproduce keys, tokens, or endpoint values found in source.
- State assumptions and cardinality risks in the Limitations section.
