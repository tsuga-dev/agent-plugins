# Trace Audit Casebook

Use this file to store reusable recurring patterns learned from real audits. Keep entries generic. Do not store service-specific lore unless it clearly generalizes.

## Pattern: Python ASGI `http receive` / `http send` child spans

- Observable symptom in Tsuga:
  - child spans such as `POST /route http receive`
  - child spans such as `POST /route http send`
  - these appear under a normal server span for the same route
- Classification:
  - span class: framework/internal span
  - direction: internal
  - correctness status: valid but noisy instrumentation
- Likely source:
  - framework auto-instrumentation in Python ASGI/FastAPI stacks
- Correct interpretation:
  - these are often internal framework child spans, not duplicate requests and not broken propagation
- Correct remediation path:
  - if low-value, suppress them in framework instrumentation config
  - for Python FastAPI instrumentation, suppress lifecycle spans via a custom `SpanProcessor` that filters by span name (`http.receive`, `http.send`), or by passing a custom `server_request_hook` to the ASGI instrumentation that skips recording those spans
- Common misdiagnosis to avoid:
  - "the service handled the request twice"
  - "trace propagation is broken"
- Example evidence fields to inspect:
  - `span.kind`
  - parent/child relationship
  - route-shaped parent span
  - matching downstream server span
- Notes on generalization:
  - applies to framework-generated lifecycle spans more broadly, not only this exact route shape

## Pattern: Outbound HTTP client spans named only `GET` / `POST`

- Observable symptom in Tsuga:
  - many `span.kind=client` spans named only by HTTP method
- Classification:
  - span class: low-information named span
  - direction: outbound/client
  - correctness status: uncertain, needs code inspection
- Likely source:
  - library default instrumentation or shared client helper naming
- Correct interpretation:
  - the call is usually real, but the naming is too generic to be useful
- Correct remediation path:
  - inspect shared outbound HTTP instrumentation and span-builder defaults before patching call sites
- Common misdiagnosis to avoid:
  - "inbound/server spans are misnamed"
  - "this is a propagation problem"
- Example evidence fields to inspect:
  - `span.kind`
  - `code.module`
  - `server.address`
  - `http.request.method`
- Notes on generalization:
  - applies to any stack where client span naming defaults collapse to verb-only names

## Pattern: `pg-pool.connect`

- Observable symptom in Tsuga:
  - frequent DB-related spans focused on pool acquisition/connect rather than useful query work
- Classification:
  - span class: DB connect span
  - direction: internal or outbound/client depending on emitted metadata
  - correctness status: valid but noisy instrumentation
- Likely source:
  - library default DB instrumentation
- Correct interpretation:
  - often useful only for specific pool-contention debugging, not for normal request trace readability
- Correct remediation path:
  - suppress connect spans when query spans already provide the useful dependency picture
- Common misdiagnosis to avoid:
  - "database tracing is broken"
- Example evidence fields to inspect:
  - span name frequency
  - duration pattern
  - presence of richer query spans nearby
- Notes on generalization:
  - applies to connection-acquisition spans across DB clients, not just Postgres

## Pattern: Custom wrapper span like `db.connect-tenant`

- Observable symptom in Tsuga:
  - custom internal span with tiny duration and little semantic value
- Classification:
  - span class: custom wrapper span
  - direction: internal
  - correctness status: valid but noisy instrumentation
- Likely source:
  - local manual instrumentation or shared helper wrapper
- Correct interpretation:
  - likely a wrapper span that duplicates visibility already available elsewhere
- Correct remediation path:
  - remove it unless it marks real work, adds attributes, or improves interpretation
- Common misdiagnosis to avoid:
  - "all manual spans are bad"
- Example evidence fields to inspect:
  - duration
  - attribute usefulness
  - relationship to more meaningful surrounding spans
- Notes on generalization:
  - applies to app-level wrapper spans that name helper boundaries but add no diagnostic value

## Pattern: Fastify hook spans like `onResponse` / `onSend`

- Observable symptom in Tsuga:
  - many tiny spans named after framework lifecycle hooks
- Classification:
  - span class: framework/internal span
  - direction: internal
  - correctness status: valid but noisy instrumentation
- Likely source:
  - framework auto-instrumentation or overlapping framework instrumentation
- Correct interpretation:
  - these are usually hook/lifecycle detail, not business operations
- Correct remediation path:
  - inspect Fastify instrumentation setup and overlapping instrumentation; suppress/filter if they dominate and add no request-level insight
- Common misdiagnosis to avoid:
  - "there is a duplicate route handler"
  - "these need to be renamed as business spans"
- Example evidence fields to inspect:
  - span name frequency
  - parent server span
  - evidence of overlapping instrumentation
- Notes on generalization:
  - applies to hook-heavy framework internals in other stacks too
