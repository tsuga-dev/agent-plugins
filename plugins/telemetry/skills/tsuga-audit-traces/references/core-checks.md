# Trace Audit Core Checks

Use this file to preserve the baseline audit responsibilities for every trace audit. The taxonomy and casebook add nuance; they do not replace these checks.

## Resource Identity

Inspect:
- `service.name`
- `service.version`
- `telemetry.sdk.name`

Flag:
- missing `service.name`
- missing version/build identity where the service is expected to provide it
- empty/incomplete resource identity that makes service-level trace analysis weaker

Do not stop at naming/noise classification if the resource identity is broken.

## Span Naming Quality

Check both failure modes:

### High-Cardinality Naming

Bad signs:
- IDs in span names
- UUIDs in span names
- raw path segments with request-specific values

Correct fix:
- static low-cardinality name
- dynamic values moved to attributes

### Low-Information Naming

Bad signs:
- client spans named only `GET`, `POST`, `PUT`, `PATCH`, `DELETE`
- names that identify only a generic verb with no operation context

Correct fix:
- improve operation/dependency-aware span naming

Do not collapse these two problems into one.

## Span Kind Discipline

Check whether:
- incoming request spans are `server`
- outbound dependency spans are `client`
- internal spans are actually internal helper/business spans

Gap detection:
- if the service clearly makes downstream HTTP/DB calls but no `client` spans appear, note a likely auto-instrumentation or manual instrumentation gap

Do not claim this gap from one trace alone unless the evidence is strong. Prefer repeated evidence from inventory plus sampled spans.

## Status Code Discipline

Check:
- are error-bearing spans using `statusCode:error` where expected?
- are spans missing error status despite clear error evidence in the same window?

HTTP interpretation rules:
- `server` span + HTTP 4xx: usually `UNSET`, not `ERROR`
- `server` span + HTTP 5xx: usually `ERROR`
- `client` span + HTTP 4xx/5xx: usually `ERROR`

Cross-check with logs when possible rather than inferring from one sample.

## Attribute Naming Quality

Inspect custom span attribute names.

Prefer:
- OTel-style dot notation such as `order.id`

Flag:
- camelCase custom names
- snake_case custom names used for new custom span attributes

Do not inspect raw attribute values unless required and safe.

## Span Events

Check whether span events exist and distinguish:

- exception events
  - these are often correct and required when status is `ERROR`
- non-exception events
  - valid, but sometimes better represented as structured logs for Tsuga searchability

Do not recommend removing exception events just because they add detail.

## Short Child Spans

Short-duration child spans are a review target, not an automatic problem.

Use the noise/removal rubric from `heuristics.md` to decide whether they are:
- useful detail
- valid but noisy instrumentation
- uncertain and needing code inspection

## Minimum Baseline Audit Coverage

Before finalizing an audit, confirm you have checked:
- resource identity
- span naming quality
- span kind discipline
- status code discipline
- attribute naming quality
- span events
- short/noisy child spans
