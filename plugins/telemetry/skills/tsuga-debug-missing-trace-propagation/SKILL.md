---
name: tsuga-debug-missing-trace-propagation
description: "Use when traces don't span multiple services, parent/child span relationships are missing, or there are orphaned spans and multiple unrelated trace IDs for a single request."
---

# Debug: Missing Trace Propagation

> **Last verified:** 2026-03-21

## When to Use

"Why are traces broken between services?", "Multiple trace IDs for the same request", "Spans from service B don't link to service A", "Context is lost when calling the downstream service", "Trace doesn't continue past the queue", "Parent span ID is missing on callee spans"

## Required Inputs

- **Caller service name** (required)
- **Callee service name** (required)
- **Transport type** (required: HTTP / gRPC / Kafka / SQS / RabbitMQ)
- **Language of caller** and **language of callee** (required for code fix)

## Workflow

### Step 1: Confirm inbound spans exist on both sides

```bash
# Check caller
tsuga spans search --query "context.service.name:<caller>" --max-results 5

# Check callee
tsuga spans search --query "context.service.name:<callee>" --max-results 5
```

If callee has NO spans at all: this is a missing instrumentation problem, not a propagation problem → route to `tsuga-debug-no-data`.

### Step 2: Look for parent span ID on callee spans

In the callee span results: is `parentSpanId` present and non-empty?

- `parentSpanId` absent or null → context not extracted (propagation is broken at extraction)
- `parentSpanId` present but points to a different trace → wrong context being propagated (likely context leak)
- `parentSpanId` present and matches a caller span → propagation is working ✅

### Step 3: Verify propagator is configured

Both the caller and callee must use the same propagator. The default is W3C TraceContext (`traceparent` / `tracestate` headers). Check:
- Is `OTEL_PROPAGATORS` set? Default: `tracecontext,baggage`
- Is a custom propagator registered that overrides the default?
- Are both services using the same propagator format?

### Step 4: Check inject/extract at the transport boundary

**For HTTP:**
- Caller: Does the HTTP client (fetch, axios, http.request, OkHttp, etc.) have the OTel HTTP client instrumentation active?
- Callee: Does the HTTP server (Express, FastAPI, Spring MVC, etc.) have the OTel server instrumentation active?
- Manual injection/extraction? Check that `propagator.inject(context, headers, setter)` and `propagator.extract(context, headers, getter)` are called

**For gRPC:**
- Caller: OTel gRPC client interceptor registered?
- Callee: OTel gRPC server interceptor registered?

**For Kafka/SQS/RabbitMQ:**
- Producer: Are trace context attributes injected into message headers/attributes?
- Consumer: Are trace context attributes extracted from message headers before starting the processing span?
- See `otel-<lang>` → `references/async-messaging.md` for detailed patterns

### Step 5: Check for accidental workflow merging

Anti-pattern: A background job reads from a queue and re-uses the producer's trace context as the parent — creating a parent-child relationship between unrelated workflows.

Correct pattern: Extract the trace context from the message as a **link** (not a parent), then start a new root span for the consumer job. The link preserves traceability without merging timelines.

If the callee is a queue consumer: verify it starts a new root span and creates a link to the producer span, rather than creating a child span.

### Step 6: Provide minimal code fix

Based on the language and transport identified, provide the minimal code change needed:
- For HTTP: enable/configure the HTTP client instrumentation
- For gRPC: add the gRPC interceptor
- For messaging: add inject/extract at the producer/consumer boundary (see `otel-<lang>` → `references/async-messaging.md`)

Load the language-specific propagation reference for the exact pattern:
- `otel-<caller-lang>` → `references/propagation.md`
- `otel-<callee-lang>` → `references/propagation.md`

### Step 7: Re-run smoke/trace verification

After applying the fix:
```bash
tsuga spans search --query "context.service.name:<callee>" --max-results 5
# Verify parentSpanId is now populated and matches a caller span
```

## Evidence Requirements

- Broken propagation = callee spans with null/missing `parentSpanId` (cite span search results)
- Wrong propagator = `OTEL_PROPAGATORS` value mismatch (ask user if not visible in CLI)
- Working propagation = callee span with `parentSpanId` matching a caller `spanId`

## Output Template

```
## Debug: Missing Trace Propagation

## Services Inspected
- Caller: <service> (<language>) → Callee: <service> (<language>)
- Transport: <HTTP / gRPC / Kafka / SQS>

## Propagation Status
| Check | Status | Evidence |
|---|---|---|
| Caller spans present | ✅/❌ | <N> spans found |
| Callee spans present | ✅/❌ | <N> spans found |
| parentSpanId on callee | ✅/❌/⚠️ | present/absent/wrong trace |
| Propagators match | ✅/❌/⚠️ unknown | <value or "not verified"> |

## Root Cause
<most likely cause — injection missing / extraction missing / propagator mismatch / workflow merge>

## Recommended Fix
<minimal code change with language-specific snippet>

## Verification
After applying the fix:
```bash
tsuga spans search --query "context.service.name:<callee>" --max-results 5
# Check: parentSpanId present and matches a caller spanId
```

## Limitations
- Propagator configuration cannot be verified directly from CLI — relies on env var inspection
- Message queue propagation requires inspecting message attribute schema (not visible in Tsuga spans)
- Fix recommendations are for the identified transport type; other transport boundaries may also need updating
```

## Safety Rules

- Do not reproduce raw span attribute values — inspect field names only
- Advisory only — this skill diagnoses and provides code examples; it does not apply changes
- If callee has no spans at all, do not diagnose as a propagation issue — route to `tsuga-debug-no-data` first

## Related Skills / Next Steps
- `otel-<lang>` → `references/async-messaging.md` — detailed messaging queue propagation patterns
- `tsuga-smoke-test` — verify after applying the fix
- `tsuga-debug-no-data` — if callee has no spans at all
- `otel-<lang>` → `references/propagation.md` — language-specific propagation code
