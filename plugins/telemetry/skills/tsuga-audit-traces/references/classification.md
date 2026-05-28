# Trace Audit Classification

Use this file to classify what kind of span problem you are looking at before recommending a fix.

## Span Classes

### Request/Server Span

- Definition: span representing inbound work owned by the service
- Typical evidence:
  - `span.kind=server`
  - route or RPC-style name
- Common false positives:
  - internal framework child spans named similarly to the server span
- Do not conclude:
  - that every similar child span is a duplicate request

### Outbound/Client Span

- Definition: span representing a downstream dependency call made by the service
- Typical evidence:
  - `span.kind=client`
  - downstream host or dependency attributes
- Common false positives:
  - method-only names that look "generic" but are still real client spans
- Do not conclude:
  - that weak naming means the call is fake or duplicated

### Framework/Internal Span

- Definition: span emitted by framework lifecycle hooks or server internals
- Typical evidence:
  - very short duration
  - nested under a normal server span
  - names like `http receive`, `http send`, `onRequest`, `onSend`, `onResponse`
- Common false positives:
  - manual wrapper spans that happen to be short
- Do not conclude:
  - that framework/internal spans are necessarily bugs

### DB Connect Span

- Definition: span representing pool acquisition or connection establishment rather than the useful query itself
- Typical evidence:
  - names like `pg.connect`, `pg-pool.connect`
  - DB-related attributes but little business value
- Common false positives:
  - real dependency spans during pool contention investigations
- Do not conclude:
  - that all DB connect spans should always be removed

### Custom Wrapper Span

- Definition: manually added app-level span that wraps a helper call but adds little semantic value
- Typical evidence:
  - internal/custom name
  - tiny duration
  - few/no useful attributes
- Common false positives:
  - genuinely valuable business boundary spans
- Do not conclude:
  - that all manual spans are bad

### Useful Operation Span

- Definition: span with independent semantic value that helps interpret the trace
- Typical evidence:
  - request boundary, query, external dependency, or meaningful business operation
  - useful attributes or parent boundary role
- Common false positives:
  - short spans that still matter
- Do not conclude:
  - that short duration alone makes the span disposable

### Low-Information Named Span

- Definition: span name is too generic to be useful
- Typical evidence:
  - HTTP client spans named only `GET`, `POST`, `PUT`, `PATCH`, `DELETE`
  - names that identify only the verb, not the operation
- Common false positives:
  - temporary library defaults that still carry the correct dependency metadata
- Do not conclude:
  - high-cardinality naming; this is the opposite problem

### High-Cardinality Named Span

- Definition: span name includes request-specific values
- Typical evidence:
  - IDs
  - UUIDs
  - raw URL path segments
- Common false positives:
  - templated route names that merely contain placeholders
- Do not conclude:
  - that generic names and high-cardinality names are the same issue

## Correctness Status

### Verified Bug

- Definition: evidence shows broken instrumentation correctness
- Examples:
  - broken parent/child linkage
  - missing error status where confirmed required
  - clearly incorrect span kind discipline

### Valid But Noisy Instrumentation

- Definition: instrumentation is producing technically valid spans that reduce readability more than they help
- Examples:
  - framework send/receive spans
  - hook spans
  - low-value connect spans

### Uncertain, Needs Code Inspection

- Definition: trace evidence suggests a problem class, but the actual source/fix location cannot be verified from Tsuga alone
- Examples:
  - suspected shared helper defaults
  - suspected overlapping instrumentation

## Direction Classes

- `inbound/server`
- `outbound/client`
- `internal`

Direction is required because similar naming problems have different fixes depending on whether the span is inbound, outbound, or internal.

## Source Classes

### Framework Auto-Instrumentation

- Typical examples:
  - ASGI hook spans
  - Fastify lifecycle spans

### Library Default Instrumentation

- Typical examples:
  - default HTTP client naming
  - default connect spans from DB instrumentation

### Shared Bootstrap/Helper

- Typical examples:
  - common OTel setup
  - shared client wrapper
  - shared tracing middleware

### Local Manual Instrumentation

- Typical examples:
  - route-local `withSpan(...)`
  - helper-local wrapper spans

## Required Classification Output

Every finding must end with:
- span class
- direction
- likely source
- correctness status

Do not recommend a fix before these fields are decided.
