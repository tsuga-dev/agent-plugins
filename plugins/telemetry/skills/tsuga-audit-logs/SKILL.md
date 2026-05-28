---
name: tsuga-audit-logs
description: "Use when asked to review log quality, improve log structure, check trace correlation in logs, or audit logging patterns for a service."
---

# Tsuga: Audit Logs

> **Requires live Tsuga connection.** This skill audits what Tsuga is actually receiving. For code-only review, see `otel-<lang>/references/audit-checklist.md`.

## Trigger

"Are my logs structured correctly?", "Review logging for service X", "Do my logs correlate with traces?", "Audit log quality", "Are we logging the right things?", "Why can't I find the trace in my logs?", "Check log structure"

## Required Inputs

- **Service name** (required — ask if missing)
- **Time window** (optional; default: `-1h`)

## Workflow

1. `tsuga services list` — confirm service exists; note `sources[]` (does service emit both logs and traces?); note `logsCount24h` and `tracesCount24h`.

2. `tsuga logs search --query "context.service.name:<name>" --from <window> --max-results 10` — inspect structure of log records: what top-level fields are present? Is `trace_id` present? Is `level` present and consistent? Is the `message` field a short description or a long blob?

3. **Correlation check:** If `sources[]` includes traces (or `tracesCount24h > 0`): check whether `trace_id` field is present in log records. If absent: this is the most impactful finding — flag immediately.

4. `tsuga logs patterns --query "context.service.name:<name>" --from <window>` — analyze dominant log patterns. Note: what fraction of total logs does the top pattern represent? Are there structural inconsistencies across patterns (some structured, some blob)?

5. `tsuga logs error-pattern-increases --team <team> --from <window>` (use the team resolved in step 1; add `--env <env>` if provided) — check whether any error patterns are growing over time. `--team` is required. Growing error patterns may indicate a regression or a newly introduced bug, even if absolute error counts are low.

6. `tsuga logs search --query "context.service.name:<name> level:ERROR" --from <window> --max-results 5` — inspect error log structure specifically. Are exception details in structured fields (`filename`, `target`) or embedded in the message string?

7. For code-side audit (OTel log bridge setup, structured logging framework configuration, trace_id injection) → `otel-<lang>/references/audit-checklist.md`

8. `tsuga routes list` — check whether a log processing route exists for this service (log enrichment, correlation processors). Note route names and processor types if found.

9. **Stop and validate with user.** Before presenting final findings, share preliminary observations: "Based on CLI evidence [and code review if applicable], here's what I see — [summary: structure state, correlation state, key gaps]. Does this match how logging is set up in this service?" Use the user's response to correct any misunderstandings before concluding.

## Checks to Perform

- **trace_id presence:** If `sources[]` includes traces, logs MUST have `trace_id` and `span_id` as top-level fields. `trace_flags` is also recommended per OTel's "Trace Context in non-OTLP Log Formats" spec. If `trace_id` is absent: "trace-log correlation missing" — highest severity finding.
- **Structured vs blob:** If log `message` field is long and contains embedded `key=value` pairs or JSON strings, it is unstructured. Structured fields should be top-level in the log record, not embedded in the message.
- **Severity discipline:** `level` field values should be exactly ERROR, WARN, INFO, or DEBUG. Inconsistent variants (`error`, `warning`, `information`, `Warning`) = finding.
- **Noise patterns:** If a single pattern from `logs patterns` has `size` > 80% of `sampleSize`, it may crowd out useful signals and make pattern-based alerts unreliable.
- **Error pattern growth:** If `error-pattern-increases` returns results, flag each growing pattern as a finding — "Error pattern X is increasing in volume (source: tsuga CLI, command: `tsuga logs error-pattern-increases`)." This complements the noise patterns check (which is about dominance, not growth).
- **Error log quality:** Error logs should include `filename` and `target` (stack context). A blob error message without structured context = reduced debuggability.
- **PII field detection:** If log field names match PII patterns (email, ssn, creditcard, password, token, secret) → warn; do not inspect or reproduce values.

## Evidence Requirements

- **"trace_id missing"** = `tsuga logs search` result confirms `trace_id` field absent in ≥ 5 sampled records AND `tracesCount24h > 0` (service is emitting traces)
- **"Unstructured log"** = log `message` field contains embedded `key=value` or JSON string confirmed in CLI output
- **"Noise pattern"** = `logs patterns` result where single pattern `size` represents > 80% of `sampleSize`
- **"Inconsistent severity"** = `level` field contains values other than ERROR/WARN/INFO/DEBUG in sampled records
- **Source code finding** = cite file path + line number; label as "source: code analysis"
- All CLI findings = label as "source: tsuga CLI, command: `<command>`"

## Output Template

```
## Log Shape Audit: <service> (<from> → <to>)
Sources: <logs / traces / both> | Patterns inspected: <N> | Sample size: <N>

## Correlation Coverage
trace_id present in sampled logs: <yes / no / partial (N of 10 records)>
[If no and tracesCount24h > 0:]
⚠️ FINDING — trace-log correlation missing (source: tsuga CLI)
Fix: Add OTel log bridge to inject trace context. See [C++](https://opentelemetry-cpp.readthedocs.io/en/latest/) · [.NET](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics) · [Go](https://pkg.go.dev/go.opentelemetry.io/otel) · [Java](https://javadoc.io/doc/io.opentelemetry) · [JS](https://open-telemetry.github.io/opentelemetry-js/) · [PHP](https://open-telemetry.github.io/opentelemetry-php/) · [Python](https://opentelemetry-python.readthedocs.io/en/latest/) · [Ruby](https://www.rubydoc.info/gems/opentelemetry-sdk) · [Rust](https://docs.rs/opentelemetry/latest/opentelemetry/)

## Structure Findings
| Finding | Evidence | Severity | Source |
|---|---|---|---|
| Unstructured blob messages | message field contains embedded key=value string | Medium | tsuga CLI |
| Inconsistent severity values | level field contains: ERROR, error, Warning | Low | tsuga CLI |
| High-noise pattern | Top pattern = N% of sampleSize | Medium | tsuga CLI |

## Error Log Quality
Error logs inspected: <N>
- Structured error context (filename, target): <present / absent>
- Exception details in dedicated fields vs embedded in message: <yes / no>

## Error Pattern Growth
[If error-pattern-increases returned results:]
| Pattern summary | Team | Env | Increase timestamps (UTC) |
|---|---|---|---|
| <pattern> | <team> | <env> | <increaseTimestamps formatted as UTC> |
[If none returned: "No growing error patterns detected in window."]

## Log Processing Route
<Route name found with processors: [list] / No processing route found for this service>

## Recommended Actions
1. [If trace_id missing] Add trace context injection to your logging setup — see [C++](https://opentelemetry-cpp.readthedocs.io/en/latest/) · [.NET](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics) · [Go](https://pkg.go.dev/go.opentelemetry.io/otel) · [Java](https://javadoc.io/doc/io.opentelemetry) · [JS](https://open-telemetry.github.io/opentelemetry-js/) · [PHP](https://open-telemetry.github.io/opentelemetry-php/) · [Python](https://opentelemetry-python.readthedocs.io/en/latest/) · [Ruby](https://www.rubydoc.info/gems/opentelemetry-sdk) · [Rust](https://docs.rs/opentelemetry/latest/opentelemetry/)
2. [If unstructured] Replace string interpolation with structured log fields (e.g., logger.info({ userId }, "User logged in") not logger.info("User " + userId + " logged in"))
3. [If noise pattern] Investigate whether top pattern can be downgraded to DEBUG or emitted at a lower frequency

## Limitations
- Log content inspection is structural only (field names and patterns); raw field values are not reproduced
- trace_id presence is checked on a sample of 10 records; actual coverage across all logs may differ
- PII field detection is name-based only — values are not inspected
- Source code findings (if any) are from the provided path — other log call sites may exist elsewhere
```

## GOOD/BAD Examples

### Structured vs Unstructured Logs

**BAD:** String concatenation / template logging
```javascript
// BAD — creates unstructured log; fields not indexable
logger.info("User " + userId + " placed order " + orderId + " for " + amount)
```

**GOOD:** Structured fields as separate keys
```javascript
// GOOD — every field is independently queryable
logger.info("order.placed", { user_id: userId, order_id: orderId, amount_cents: amount })
```

### Trace Correlation

**BAD:** Logs missing `trace_id` even though the service emits traces
```
// BAD — log has no trace context
{"level":"INFO","message":"Order placed","order_id":"ord-123","timestamp":"..."}
```

**GOOD:** `trace_id` and `span_id` injected as top-level fields
```
// GOOD — correlatable with traces
{"level":"INFO","message":"order.placed","order_id":"ord-123","trace_id":"4bf92f...","span_id":"00f067...","timestamp":"..."}
```

### Severity Consistency

**BAD:** Non-standard severity level names
```
// BAD — variants cause filtering to fail in observability tools
{"level": "warning", "message": "..."}   // should be WARN
{"level": "error", "message": "..."}     // should be ERROR (capitalized)
{"level": "err", "message": "..."}       // non-standard abbreviation
```

**GOOD:** Standard ALL-CAPS severity levels: ERROR, WARN, INFO, DEBUG

### Error Log Quality

**BAD:** Error log with no context
```
{"level": "ERROR", "message": "Something went wrong"}
```

**GOOD:** Error log with exception type, message, and stack context
```
{"level": "ERROR", "message": "order.create.failed", "exception.type": "ValidationError", "exception.message": "Invalid quantity: -1", "exception.stacktrace": "...", "order_id": "ord-123"}
```

## Safety Rules

- Never reproduce raw log content or field values — inspect field names and structure only
- If `context.sensitive == "true"` appears in any record: warn user and stop reporting field-level details for that service
- If field names match PII patterns (email, ssn, credit_card, password, token, secret): warn and stop — do not inspect values
- Advisory only — propose fixes, do not apply code changes; all proposed changes require explicit user confirmation

**Instrumentation Quality Rules (A1–A5):**

A1: Code reading is allowed and expected — reading source files is how you gather evidence.
A2: Label all findings with their evidence source: "source: tsuga CLI" or "source: code analysis".
A3: Refactor proposals require explicit user confirmation before writing code.
A4: Validate your understanding of existing instrumentation before concluding anything is missing.
A5: Distinguish advisory findings (suspected issues) from verified findings (confirmed via CLI data).

## Related Skills / Next Steps
- `otel-<lang>/references/logs.md` — trace-log correlation setup if trace_id is missing
- `tsuga-smoke-test` — verify after fixing log issues
- `otel-<lang>/references/audit-checklist.md` — code-side audit (log bridge setup, structured logging)
- `signal-choice-advisor` — if log structure needs redesign
