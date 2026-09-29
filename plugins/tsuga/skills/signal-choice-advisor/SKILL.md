---
name: signal-choice-advisor
description: "Decides how to model an observation before any code is written: which OpenTelemetry signal to emit, which instrument to pick, what to name it against the semantic conventions, where the attribute belongs, and whether a proposed metric dimension is low-cardinality enough to ship. Use when choosing between a metric, span, structured log or resource attribute, between Counter, Histogram, UpDownCounter and Observable Gauge, or when someone describes something they want to observe without having decided how to instrument it. Advisory only and it never writes code: route the SDK implementation to otel-instrumentation."
---

Help the user choose between metric / span / structured log / resource attribute, and between Counter / Histogram / UpDownCounter / Observable Gauge. Advisory: this skill decides the signal, the name, and the placement, and never writes the code.

## Inputs

- What the developer is trying to measure or observe (required - ask if missing; a vague requirement produces a vague recommendation).
- Service name (optional - lets you check whether the service already emits traces).
- Language/runtime (optional - enables a concrete implementation sketch).

## Documentation grounding

Tsuga docs decide the answer. Use `tsuga docs search`, then `tsuga docs get`; cite `path`, `title`, and `link` when docs were used.

| Need                                                           | Page                                                               |
| -------------------------------------------------------------- | -------------------------------------------------------------------- |
| Signal and instrument choice, bounded metric attributes        | `data-collection/guides/how-to-choose-a-telemetry-signal`          |
| Resource attribute placement and setup                         | `data-collection/guides/how-to-add-resource-attributes`            |
| Where each part of OTLP lands in Tsuga                         | `data-collection/guides/default-mapping-for-opentelemetry-formats` |
| Log-trace correlation fields                                   | `data-collection/guides/how-to-correlate-logs-and-traces`          |
| Span kind                                                      | `data-collection/guides/how-to-choose-a-span-kind`                 |
| Anti-patterns, span events, lowercasing, measuring cardinality | `references/telemetry/signal-choice`                               |
| Mobile RUM events, and what each one is named                   | `data-collection/mobile/rum-events`                                |
| Browser RUM event naming                                       | `data-collection/browser/grafana-faro`                             |
| Continuous profiles                                            | `data-collection/profiling`                                        |

If Tsuga docs do not settle a name, use the OpenTelemetry semantic conventions at https://opentelemetry.io/docs/specs/semconv/ and the attribute registry before inventing one. If neither covers the recommendation, label it `Recommendation (not verified in Tsuga or OTel docs)`.

## Judgment the docs do not carry

- "Duration of X" where X is already a span: the span answers it. Add a Histogram only when the aggregate distribution is the question and the trace sample rate cannot answer it.
- "Count of X" where X is already a span: aggregate the span count. A parallel Counter drifts from it and has to be reconciled forever.
- "Did Y happen inside operation Z": a structured log carrying `trace_id` and `span_id` - not a child span, and not a span event.
- RUM events and continuous profiles are separate ingestion paths, not a fifth instrument to choose between. Reach for them when the question is frontend timing, a crash, or CPU attribution, and say so explicitly rather than modelling it as a metric. Both have their own views. RUM has no widget source at all; profiles arrive as `profile.samples.<service>` metrics, so a widget can chart sample counts but not the call stack. A recommendation that has to land on a dashboard as anything richer has to be `logs`, `metrics` or `traces`.
- Reject outright any metric dimension that grows with users, orders, sessions, request IDs, raw URLs, query strings or trace IDs. Measure every other candidate rather than guessing, and never quote a series-count zone or threshold - Tsuga publishes none.

## Workflow

1. Gather the requirement. If it is too vague to name an operation, ask: "What specific operation, event, or measurement are you trying to capture?"
2. If a service name was given: `tsuga services list`, then read `traceRequestRate`. A value means the service already emits traces, so check whether the proposal duplicates a span aggregation. An absent field means the query failed, not zero.
3. If the metric already exists: `tsuga metrics get` for its type, unit, temporality and attribute names. Where it returns `attributeCardinalities`, read them as periodically refreshed estimates; where it returns attribute names only, measure cardinality with the aggregation in `references/telemetry/signal-choice`.
4. Recommend the signal, the name, the placement and the dimensions. Name the alternatives you rejected and why.
5. If you read source or live telemetry, share what you saw and ask whether it matches how the service instruments itself.
6. Hand the SDK implementation off - this skill never writes instrumentation code. Where an `otel-instrumentation` skill is available, it owns that step.

## Verification

After the change ships, confirm the signal arrives: `tsuga traces search` or `tsuga logs search` for a new span or log, an `tsuga aggregation scalar` count over the window for a new metric, with the metric name as the aggregate `field` - `count` on `metrics` fails without one. The metric catalog ignores the time range, so a name in `tsuga metrics list` and a `tsuga metrics get` hit both say the name was seen at some point, never that a datapoint landed in the window.

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
- If cardinality was not measured, state it as an unquantified risk rather than guessing a number.
- If OTel semconv defines a standard name, always prefer it.
- Advisory output only. If you propose a source change, show it and require explicit confirmation before any edit.
- Never read `.env`, `*.secret`, `*credentials*`, or `*token*` files, and never reproduce keys, tokens, or endpoint values found in source.
- State assumptions and cardinality risks in the Limitations section.
