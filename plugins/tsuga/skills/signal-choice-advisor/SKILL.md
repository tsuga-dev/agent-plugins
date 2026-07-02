---
name: signal-choice-advisor
description: "Use when choosing an OpenTelemetry signal, instrument, or telemetry name: metric vs span vs log, counter vs histogram vs gauge, span event vs child span, resource/span/log/metric attribute naming, semantic convention checks, deployment.environment migration, bounded dimensions, cardinality estimates, high-cardinality risk, or whether an observation belongs in traces, metrics, logs, or resource attributes."
---

# Signal Choice Advisor

Use this for telemetry modeling, semantic convention naming, placement, and cardinality. It is advisory by default; do not write code changes from this skill.

## Runtime Docs Lookup

For docs lookup rationale and docs-error behavior, follow `tsuga-cli`; examples omit `--rationale` for brevity.

Fetch docs when naming, modeling, or explaining Tsuga mapping:

| Need | Fetch |
|---|---|
| Resource attributes | `tsuga docs get data-collection/guides/how-to-add-resource-attributes` |
| OTel to Tsuga mapping | `tsuga docs get data-collection/guides/default-mapping-for-opentelemetry-formats` |
| Signal choice | `tsuga docs get data-collection/guides/how-to-choose-a-telemetry-signal` |
| Common anti-patterns | `references/signal-choice.md` |

Use Tsuga docs and bundled references first. If they do not cover the naming decision, check the official OpenTelemetry semantic convention docs before inventing a name:

```text
https://opentelemetry.io/docs/specs/semconv/
```

If neither Tsuga docs nor official OTel docs cover the recommendation, label it as `Recommendation (not verified in Tsuga or OTel docs)`.

## Inputs

- What the developer is trying to measure or observe. Ask if missing.
- Service name, if live Tsuga context is needed.
- Language/runtime, if an implementation sketch is requested.

## Signal Selection

| Signal | Use when | Do NOT use when |
|---|---|---|
| Counter | Counting discrete events that only increase: requests, errors, retries, cache misses | Measuring duration; use Histogram or Span |
| Histogram | Measuring distributions: latency, payload size, queue wait time | Debugging individual requests; use Spans |
| UpDownCounter | Current state that fluctuates: queue depth, active connections | Tracking totals that never decrease |
| Observable Gauge | Spot measurement sampled at collection time: CPU%, heap usage | Per-request counting |
| Span | An operation with meaningful duration, causality, and sampling value | A point-in-time occurrence |
| Structured log with trace context | Timestamped occurrence inside a request: exception detail, cache miss, state change, business event | Aggregate health measurements |
| Resource attribute | Identity that does not change per operation: service, version, environment, host | Per-request values |

Key rules:

- Duration of X -> prefer Span if it is already an operation; use Histogram for aggregate-only distributions.
- Count of X where X is already a span -> prefer span count aggregation over a duplicate Counter.
- Point-in-time diagnostic event -> prefer structured log with `trace_id`/`span_id`; span events remain valid for exception recording.
- Child spans are for operations with meaningful duration, not "thing happened" markers.

## Naming And Cardinality Rules

- Check Tsuga docs first, then official OTel docs, before inventing any span, metric, log, or resource attribute name.
- Use standard names even when the convention is Development status.
- Resource attributes describe process/service identity and environment. Set them once, not per span.
- Use `deployment.environment.name`, not deprecated `deployment.environment`.
- Metric attributes must be bounded and low-cardinality.
- Use `http.route`, not raw `url.path`, for HTTP metric dimensions.
- Never use user IDs, request IDs, order IDs, raw URLs, query strings, or trace IDs as metric dimensions.
- Do not encode service name, environment, version, or units in metric names.

| Belongs on | Use for |
|---|---|
| Resource | `service.name`, `service.version`, `service.instance.id`, `deployment.environment.name`, `k8s.pod.uid`, `host.name` |
| Span | Request-specific fields such as `http.request.method`, `http.response.status_code`, `db.operation.name`, `db.query.text` |
| Span event | Exceptions: `exception.type`, `exception.message`, `exception.stacktrace` |
| Log record | Per-log fields plus `trace_id` and `span_id` correlation fields |
| Metric datapoint | Low-cardinality dimensions such as `http.route`, status code, method, or `db.system.name` |

## Cardinality Check

Estimate metric series count by multiplying unique values across all dimensions. If any dimension could be unique per request, reject it as a metric dimension. The zones below are heuristics; cite Tsuga CLI evidence when making a verified finding.

| Unique time series | Zone | Action |
|---|---|---|
| < 1,000 | Minimal | OK |
| 1,000-10,000 | Ideal | Healthy |
| 10,000-50,000 | Acceptable | Monitor growth |
| 50,000-100,000 | Caution | Investigate before adding more dimensions |
| 100,000-1,000,000 | Danger | Likely ingestion/query risk |
| > 1,000,000 | Critical | Do not ship without redesign |

## Workflow

1. Ask what specific operation, event, or measurement the user wants to capture if unclear.
2. If using live Tsuga context, use explicit `--from`/`--to` and cite the exact read-only command and value used. For metric metadata/cardinality checks, start with `tsuga metrics get <name> --from <from> --to <to>`.
3. Apply signal choice, naming, placement, and cardinality rules.
4. If code or Tsuga evidence was inspected, share preliminary observations and ask: "Does this match your understanding of how this service instruments itself?"
5. If language-specific code is requested, route to `otel-instrumentation`; do not generate code from this skill.

## Output Template

```markdown
## Recommendation
## Evidence Used
## Reasoning
## Semantic Convention Check
## Cardinality
## Understanding Check (omit if no code or Tsuga evidence was inspected)
## Verification
## Limitations
```

## Related Skills / Next Steps

- `otel-instrumentation` - SDK implementation after the signal and naming decision is made.
- `otel-collector` - Collector transforms, filters, routing, redaction, and OTTL.
- `tsuga-audit` - audit existing metric design and broader telemetry quality issues.
- `tsuga-debug-telemetry-ingestion` - verify the signal arrives after implementation.

## Safety Rules

- Advisory output only; if proposing source changes, show the proposed change and require explicit user confirmation before any edit.
- Never read `.env`, `*.secret`, `*credentials*`, or `*token*`.
- Never reproduce keys, tokens, or endpoint values found in source.
- Label findings as `source: code analysis` or `source: tsuga CLI`.
- Label unverified advice as `Recommendation (not verified in Tsuga or OTel docs)`. Label verified findings as `Finding (source: tsuga CLI, command: <command>, value: <value>)`.
- State assumptions and cardinality risks in `## Limitations`.
