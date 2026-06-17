---
name: tsuga-audit-metrics
description: 'Use when asked to review metric design, check metric naming, audit metric quality, or validate a custom metric.'
---

# Tsuga: Audit Metrics

> **Requires live Tsuga connection.** This skill audits what Tsuga is actually receiving. For code-only review, see `otel-<lang>/references/audit-checklist.md`.

## Trigger

"Are my metrics named correctly?", "Review the metrics for service X", "Is this metric name right?", "Check metric quality", "Audit our custom metrics", "Do our metrics follow OTel conventions?"

## Inputs

- **Service name or metric name filter** (required — ask if missing)
- **Source code path** (optional; enables code-level findings in addition to CLI evidence)

## Workflow

1. `tsuga metrics list` — list all metrics. If service name provided, identify metrics by name prefix or pattern that matches the service. Note: if the service uses a non-standard naming prefix, ask the user to confirm which metrics belong to this service.

2. For each metric found: `tsuga metrics get <name>` — extract description, type, unit, and label/attribute keys.

3. Apply naming rule checks (see below) to every metric name, type, and unit combination.

4. For each metric with suspect high-cardinality attributes: run `tsuga aggregation scalar -d '{"timeRange": {"from": <unix_1h_ago>, "to": <unix_now>}, "dataSource": "metrics", "queries": [{"id": "q1", "dataSource": "metrics", "aggregate": {"type": "count"}, "filter": "<metric.name>"}], "groupBy": [{"fields": ["<attr>"], "limit": 100}], "formula": "q1"}'`
   If result returns 100 rows (limit reached), flag as high-cardinality risk.

5. For code-side audit (instrument type correctness, OTel SDK init, metric view configuration) → `otel-<lang>/references/audit-checklist.md`

6. `tsuga quality-reports list` (pass `--cluster <id>` in multi-cluster orgs) — flat array of rule-evaluation rows. Filter `.[] | select(.status == "failed")` for failures related to metric naming or instrumentation for this service. Report timestamp = `min(.[].createdAt)`; flag if > 48h ago.

7. **Stop and validate with user.** Before presenting final findings, share preliminary observations: "Here is what I found so far — [summary of naming issues, instrument type concerns, cardinality risks]. Does this match your understanding of how metrics are instrumented in this service?" Adjust findings based on user context before concluding.

## Naming Rules

Source: OTel specification (https://opentelemetry.io/docs/specs/otel/metrics/supplementary-guidelines/#instrument-naming)

**Unit validation (UCUM notation):**
| Unit | Use for |
|---|---|
| `ms` | Latency, duration |
| `s` | Long durations |
| `By` | Memory, payload size |
| `1` | Ratios, fractions (not `%`) |
| `{request}` | Request counts |
Never encode units in the metric name — set the `unit` field instead.

| Rule                                    | Bad example                     | Good example                                                             |
| --------------------------------------- | ------------------------------- | ------------------------------------------------------------------------ |
| No service name in metric name          | `web_backend_request_count`     | `http.server.request.count` (service identity in `context.service.name`) |
| No environment/version in metric name   | `prod_latency_ms`, `v2_errors`  | `http.server.request.duration`                                           |
| No units in metric name                 | `latency_ms`, `memory_bytes`    | `request.duration` with `unit: ms`                                       |
| OTel dot notation (not underscores)     | `http_server_request_duration`  | `http.server.request.duration`                                           |
| Verb-object pattern                     | `duration` (missing namespace)  | `http.server.request.duration`                                           |
| Counter must not describe current state | `active_connections` as Counter | `active_connections` as UpDownCounter                                    |
| Histogram for distributions             | `request_duration` as Counter   | `request.duration` as Histogram                                          |

## GOOD/BAD Examples

### Metric Name Examples

**BAD:** `web_backend_http_requests_total`
**Why wrong:** Contains service name (`web_backend`) in metric name — service identity belongs in resource attributes, not the metric name.
**GOOD:** `http.server.request.count` (with `service.name` resource attribute)

---

**BAD:** `request_latency_ms` with instrument type Counter
**Why wrong:** (1) Unit `ms` is in the metric name — it belongs in the `unit` field. (2) Latency is a distribution — should be a Histogram, not a Counter.
**GOOD:** `http.server.request.duration` with Histogram instrument, unit: `ms`

---

**BAD:** `active_users` with instrument type Counter
**Why wrong:** Counter is monotonically increasing — it cannot represent a current count that goes up and down.
**GOOD:** `active_users` with UpDownCounter instrument

### Cardinality Examples

**BAD:** Metric dimension `user_id` (or `user.id`)

```
histogram.record(duration, {"user.id": userId, "http.route": "/api/orders"})
```

**Why wrong:** `user_id` has unbounded cardinality — one unique value per user → millions of time series.
**GOOD:** Remove `user.id` from metric dimensions; use it as a span attribute instead:

```
histogram.record(duration, {"http.route": "/api/orders"})  // Low-cardinality dims only
span.setAttribute("user.id", userId)                        // High-cardinality → spans
```

---

**BAD:** Metric dimension `url.path` with raw paths like `/api/orders/123/items`
**Why wrong:** Raw paths have unbounded cardinality.
**GOOD:** Use parameterized `http.route`: `/api/orders/{id}/items`

## Instrument Type Rules

| Instrument       | Correct use                                                              |
| ---------------- | ------------------------------------------------------------------------ |
| Counter          | Monotonically increasing totals (requests processed, errors, retries)    |
| UpDownCounter    | Fluctuating current values (queue depth, active connections, cache size) |
| Histogram        | Distributions — latency, payload size, queue wait time                   |
| Observable Gauge | Values sampled at collection time (CPU %, memory usage, thread count)    |

**Detection heuristic (source: CLI):** If a metric's description contains "current", "active", "open", "in-flight", or "pending" AND its type is Counter: likely wrong instrument type.

**Detection heuristic (source: CLI):** If a metric's description contains "duration", "latency", "time", or "size" AND its type is Counter or Gauge: likely should be Histogram.

## Evidence Requirements

- **Naming violation** = cite the metric name + the specific rule violated + the corrected form
- **Cardinality finding** = cite groupBy result: "N distinct values observed for attribute X in 1h window (limit 100 — actual cardinality may be higher)"
- **Instrument type finding** = cite metric description + observed type + reasoning for recommended type
- **Source code finding** = cite file path + line number + what was observed; label as "source: code analysis"
- All CLI findings = label as "source: tsuga CLI, command: `<command>`"

## Output Template

```
## Metric Shape Audit: <service/filter> (<N> metrics inspected)

## Summary
Metrics audited: <N> | Naming issues: <N> | Instrument type issues: <N> | Cardinality risks: <N>

## Naming Findings
| Metric | Issue | Corrected Form | Source |
|---|---|---|---|
| <metric.name> | <rule violated> | <recommended.name> | tsuga CLI |

## Instrument Type Findings
| Metric | Current Type | Issue | Recommended Type | Source |
|---|---|---|---|---|
| <metric.name> | Counter | Metric description says "current X" — fluctuating state should use UpDownCounter | UpDownCounter | tsuga CLI |

## Cardinality Risk Attributes
| Metric | Attribute | Distinct Values | Risk | Source |
|---|---|---|---|---|
| <metric.name> | <attr> | >100 (limit reached) | High — possible per-request identifier | tsuga CLI |

## Quality Report Correlation
<N> quality rule failures relate to metric instrumentation (report generated: <min(rows.createdAt)>)
[If derived timestamp > 48h ago: ⚠️ Quality report is stale — results may not reflect current state]

## Recommended Actions
1. Rename <metric.name> to <corrected.name> — eliminates service-identity-in-name violation
2. Change <metric.name> instrument type from Counter to UpDownCounter — metric describes fluctuating state
3. Remove <attribute> from <metric.name> dimensions — high-cardinality risk; use span attribute or log field instead

## Limitations
- Cardinality estimates via groupBy are approximate (capped at 100 distinct values in the query window)
- Instrument type findings from CLI are based on observed data shape and description text — confirm intent by reading source code
- Naming analysis covers metrics visible in Tsuga; metrics not yet emitted cannot be audited
- Source code findings (if any) are from the provided path only — other metric definitions may exist
```

## Related Skills / Next Steps

- `tsuga-metric-naming-fix` — apply renames found in this audit
- `tsuga-smoke-test` — verify metrics after fixes
- `otel-<lang>/references/audit-checklist.md` — code-side audit (instrument type, SDK init, metric views)
- `signal-choice-advisor` — if instrument type is wrong, get a redesign recommendation

## Safety Rules

- Cardinality estimates are approximate — always label as "proxy, not measurement"
- Never recommend deleting a metric without confirming it has no aggregation results (unused = no data points returned)
- Instrument type recommendation is advisory — the correct type depends on SDK intent, not just the metric name
- Do not reproduce raw attribute values from CLI output — inspect attribute names and types only
- Advisory only — propose changes, do not apply them; metric renaming requires explicit user confirmation

**Instrumentation Quality Rules (A1–A5):**

A1: Code reading is allowed and expected — reading source files is how you gather evidence.
A2: Label all findings with their evidence source: "source: tsuga CLI" or "source: code analysis".
A3: Refactor proposals require explicit user confirmation before writing code.
A4: Validate your understanding of existing instrumentation before concluding anything is missing.
A5: Distinguish advisory findings (suspected issues) from verified findings (confirmed via CLI data).
