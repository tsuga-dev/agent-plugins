# Well-Instrumented Service — Quick Reference Checklist

A service is well-instrumented when its telemetry allows you to: detect problems, localize their source, and explain their cause. Emit only telemetry that serves one of these three purposes.

## Signal Scope (fill in before checking off items)

| Signal | In scope? | Checked? |
|--------|-----------|----------|
| Traces | yes / no | [ ] |
| Logs | yes / no | [ ] |
| Metrics | yes / no | [ ] |

Only check off items below for signals that are **in scope**. Skip sections for signals marked "no".

## Signal Density Rule

> Only emit telemetry that **detects**, **localizes**, or **explains** a problem.

Reject telemetry that:
- Duplicates what the platform/auto-instrumentation already emits
- Has unbounded cardinality (user IDs, request IDs as metric dimensions)
- Emits at high frequency with no aggregation plan (e.g., per-row DB metrics)

## Checklist by Signal Type

### Traces ✓
- [ ] Every inbound request creates a SERVER root span
- [ ] Every outbound call (HTTP, gRPC, DB, queue) creates a CLIENT or PRODUCER child span
- [ ] Span names are low-cardinality (no IDs, no raw URLs — use templates like `GET /users/{id}`)
- [ ] Span kinds are correct: SERVER (inbound), CLIENT (outbound sync), PRODUCER (async send), CONSUMER (async receive), INTERNAL (local logic)
- [ ] HTTP span status follows kind rules: SERVER 4xx → UNSET, SERVER 5xx → ERROR; CLIENT 4xx → ERROR, CLIENT 5xx → ERROR
- [ ] Error spans set status to ERROR AND record an exception event
- [ ] Cron jobs / background tasks / CLI commands wrap in a manual SERVER root span
- [ ] Trace context propagated through async boundaries (queues, workers)

### Metrics ✓
- [ ] Request rate: derived from `http.server.request.duration` histogram bucket counts (no separate counter — semconv does not define `http.server.request.count`)
- [ ] Request duration: `http.server.request.duration` (Histogram, unit: s)
- [ ] Active requests: `http.server.active_requests` (UpDownCounter) if relevant
- [ ] Error rate derivable from above (not a separate metric unless business-critical)
- [ ] No service name in metric name
- [ ] No units in metric name (use unit field)
- [ ] No per-request unique IDs as metric dimensions

### Logs ✓
- [ ] Logs are structured (JSON or key=value fields, not concatenated strings)
- [ ] `trace_id` and `span_id` present as top-level fields when a trace is active
- [ ] Severity uses standard levels: ERROR, WARN, INFO, DEBUG
- [ ] Error logs include exception type, message, and stack trace context
- [ ] No sensitive data in log fields (passwords, tokens, PII — see `references/sensitive-data.md`)

### Resource Attributes ✓
- [ ] `service.name` set (REQUIRED)
- [ ] `service.version` set
- [ ] `deployment.environment.name` set
- [ ] `service.instance.id` set (UUID v4 or derived from pod UID)
- [ ] On Kubernetes: `k8s.pod.uid`, `k8s.pod.name`, `k8s.node.name`, `k8s.container.name` set via downward API

## Gaps That Auto-Instrumentation Does NOT Cover

These always require manual instrumentation regardless of framework:

- Business logic spans (e.g., order processing, payment workflow)
- Cron jobs, scheduled tasks, CLI commands (no inbound HTTP → no auto root span)
- Custom metrics (business KPIs, queue depths, cache hit rates)
- Trace context propagation in background jobs that receive from a queue
- Trace-log correlation (log bridge or manual injection of trace_id/span_id)
