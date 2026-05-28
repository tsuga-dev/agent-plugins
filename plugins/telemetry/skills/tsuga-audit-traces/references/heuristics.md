# Trace Audit Heuristics

Use this file for practical detection and interpretation rules.

## Parent/Child Interpretation

- If `... http receive` or `... http send` appears as a short-lived child under a normal server span for the same route, classify it as likely framework noise before considering bugs.
- If a suspicious child span shares the route shape of its parent server span, inspect the parent/child relationship first and the name second.
- In multi-service traces, explicitly identify upstream server span, downstream client span, and downstream server span before diagnosing any downstream internal child span.

## Short-Duration Span Interpretation

- `0ms` or near-zero duration is weak evidence by itself.
- Short duration becomes meaningful only when combined with:
  - high frequency
  - low semantic value
  - little/no useful attributes
  - redundant visibility already provided elsewhere
- Do not recommend deletion or suppression from duration alone.

## Low-Information HTTP Client Span Detection

Treat this as a distinct class from high-cardinality naming.

Strong signal:
- `span.kind=client`
- `span.name` equals exactly one HTTP method token such as:
  - `GET`
  - `POST`
  - `PUT`
  - `PATCH`
  - `DELETE`

Inspect supporting fields when available:
- `code.module`
- `code.file.path`
- `server.address`
- `http.request.method`

Interpretation rule:
- method-only client span names usually indicate weak outbound instrumentation naming or library defaults
- they are not, by themselves, evidence of propagation bugs or duplicate requests

## High-Cardinality Path/ID Detection

Treat as high-cardinality naming only when the name contains request-specific values such as:
- numeric IDs
- UUIDs
- raw entity path segments

Do not confuse:
- `GET /users/{id}` with high-cardinality naming
- `GET` with high-cardinality naming

## Duplicate-Instrumentation Suspicion

Treat duplicate instrumentation as a hypothesis, not a conclusion.

Check for evidence that noisy spans may come from:
- framework plugin instrumentation
- language auto-instrumentation
- manual spans
- exporter-time filtering gaps
- overlapping instrumentation packages for the same framework

Do not conclude duplicate instrumentation from:
- similar names alone
- short duration alone
- one child span under a healthy server span

## Low-Value Span Removal Rubric

A span is a suppression/removal candidate when most of these are true:
- high frequency
- mostly `0ms` or very short duration
- no meaningful attributes
- no independent semantic value
- not useful as a parent boundary
- duplicates visibility already available through better spans, logs, or metrics

If some criteria are true but the span still marks an important boundary, prefer keeping or renaming it rather than deleting it.

## Do Not Over-Diagnose Rules

- Do not call framework noise a correctness bug unless linkage or semantics are actually broken.
- Do not call low-information client naming a server-side problem unless the span direction is confirmed.
- Do not call child framework spans duplicate requests unless the trace actually shows an extra client/server pair.
- Do not call custom wrapper spans useless unless they truly add no semantic boundary or attributes.
- Do not call every suspicious pattern "missing propagation."

## Confidence Rules

Use high confidence when:
- the pattern matches a known class
- parent/child shape is visible
- metadata supports the source classification

Use medium confidence when:
- the pattern fits, but the exact source layer is inferred

Use lower confidence when:
- the trace tree is incomplete
- Tsuga evidence is partial
- the fix surface depends on repo-specific shared code
