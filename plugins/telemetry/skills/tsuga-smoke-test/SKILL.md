---
name: tsuga-smoke-test
description: "Use when asked to check if OTel is working, confirm a metric or span is showing up, validate post-deploy instrumentation, or verify a specific signal is being received."
---

# Telemetry Smoke Test

## Trigger

"Is my new metric showing up in Tsuga?", "Did my trace instrumentation deploy correctly?", "Verify telemetry for service X after the deploy", "Check that my logs are appearing", "Confirm the telemetry is working"

## Required Inputs

- **Service name** (required — ask if missing)
- **What to verify** (optional: specific metric name, span name, or log field; default: all three signals)
- **Time window** (optional; default: `-15m` — recent window for post-deploy verification)

## Workflow

Documentation query for validation after instrumentation, collector, provider integration, or ingestion-key changes:

```bash
tsuga docs get data-collection/guides/how-to-validate-telemetry-arrival-in-tsuga
```

Documentation queries for missing-signal troubleshooting:

```bash
tsuga docs get data-collection/guides/how-to-troubleshoot-missing-telemetry
tsuga docs get data-collection/opentelemetry/configure-otlp-export
```

1. `tsuga services list` — confirm service appears; check `lastSeenAt` is within the last 15 minutes (recent = post-deploy); note `sources[]` and 24h counters (`logsCount24h`, `tracesCount24h`)
   - If service not found at all: stop with "Service not found in Tsuga — check ingestion key and OTLP endpoint configuration"
   - If `logsCount24h == 0` AND `tracesCount24h == 0`: stop with same message

2. Run all three signal checks in parallel:

   a. **Metrics check:**
      - `tsuga metrics list` — check expected metric names exist for this service
      - If a specific metric name was provided: `tsuga metrics get <name>` — confirm it exists
      - `tsuga aggregation scalar -d '{"timeRange": {"from": <unix_from>, "to": <unix_to>}, "dataSource": "metrics", "queries": [{"id": "q1", "dataSource": "metrics", "aggregate": {"type": "count"}, "filter": "<metric.name>"}], "formula": "q1"}'`
        count > 0 confirms data points arriving

   b. **Traces check:**
      - `tsuga traces search --query "context.service.name:<name>" --from <window> --max-results 3`
      - Confirm spans present; note `resourceAttributes.service.name` value; note span names seen

   c. **Logs check:**
      - `tsuga logs search --query "context.service.name:<name>" --from <window> --max-results 3`
      - Confirm logs present; check whether `trace_id` field is present in records

3. **Cross-signal correlation check:** If both logs and traces are present:
   - `tsuga logs search --query "context.service.name:<name> trace_id:*" --from <window> --max-results 3`
   - Confirm `trace_id` is populated (not null/empty) in results

4. Report pass/fail per signal with evidence citations.

## Evidence Requirements

- **Metric arriving** = `tsuga aggregation scalar` returns count > 0 for this metric in the window
- **Traces arriving** = `tsuga traces search` returns ≥ 1 span in the window
- **Logs arriving** = `tsuga logs search` returns ≥ 1 log record in the window
- **Correlation working** = log records contain non-empty `trace_id` field; `trace_flags` presence is also checked (recommended per OTel "Trace Context in non-OTLP Log Formats" spec)

## Output Template

```
## Telemetry Smoke Test: <service> (<from> → <to>)
Service last seen: <lastSeenAt> | Sources in registry: <sources[]>

## Signal Checklist
| Signal | Status | Evidence |
|---|---|---|
| Metrics | ✅ PASS / ❌ FAIL / ⚠️ NOT TESTED | <N> data points in window for <metric.name> |
| Traces | ✅ PASS / ❌ FAIL | <N> spans in window |
| Logs | ✅ PASS / ❌ FAIL | <N> log records in window |
| Trace-log correlation | ✅ PASS / ❌ FAIL / ⚠️ NOT TESTED | trace_id present: yes/no; trace_flags present: yes/no |

## Resource Identity Check (from traces)
service.name in resourceAttributes: <value / MISSING>
service.version in resourceAttributes: <value / MISSING>

## Findings
- ✅ All signals present and correlated — instrumentation appears to be working correctly
- ❌ <signal> not found in window — check: <specific actionable diagnosis>

## Diagnosis if FAIL

**Metrics not found:**
1. Check `OTEL_EXPORTER_OTLP_ENDPOINT` is set to `https://ingest.<region>.tsuga.cloud:443`
2. Verify `tsuga-ingestion-key` header is present in OTLP headers
3. Confirm `PeriodicExportingMetricReader` export interval has elapsed (default 60s — try a wider window)

**Traces not found:**
1. Check `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` is configured
2. Confirm SDK is initialized before first request
3. Check sampler is not dropping all spans (AlwaysOff)

**Logs not found:**
1. Check `OTLPLogExporter` is configured and `BatchLogRecordProcessor` is attached
2. Confirm log level threshold is not filtering relevant records

**trace_id missing from logs:**
1. Log bridge/transport not attached to OTel context — see language API reference: [C++](https://opentelemetry-cpp.readthedocs.io/en/latest/) · [.NET](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics) · [Go](https://pkg.go.dev/go.opentelemetry.io/otel) · [Java](https://javadoc.io/doc/io.opentelemetry) · [JS](https://open-telemetry.github.io/opentelemetry-js/) · [PHP](https://open-telemetry.github.io/opentelemetry-php/) · [Python](https://opentelemetry-python.readthedocs.io/en/latest/) · [Ruby](https://www.rubydoc.info/gems/opentelemetry-sdk) · [Rust](https://docs.rs/opentelemetry/latest/opentelemetry/)
2. For pino (Node.js): add `pino-opentelemetry-transport` and `formatters.log` context injection
3. For Python logging: ensure `LoggingInstrumentor().instrument()` is called after TracerProvider is set up

## Limitations
- Smoke test uses a short window (<window>); metrics with long export intervals (default 60s) may not appear yet — try `--from -1h` before diagnosing a failure
- Negative result in a short window is not conclusive failure
- 24h counters from services list may reflect activity before the current deployment
- Cardinality of metric attributes is not checked here — see tsuga-audit-metrics for that
```

## Related Skills / Next Steps
- `tsuga-debug-no-data` — deep-dive if smoke test fails (signals missing)
- `tsuga-debug-missing-trace-propagation` — if traces don't link across services
- `otel-instrumentation` — full cross-signal audit (routes to per-lang `references/audit-checklist.md`)
- `otel-instrumentation` — trace-log correlation setup (routes to per-lang `references/logs.md`)

## Safety Rules

- Never claim instrumentation is "broken" from a negative result in a short window — state it as "not observed in window X"
- Do not reproduce raw log or span content — inspect field presence only
- If `context.sensitive == "true"` appears in any record: note it and stop field-level inspection for that service
- `lastSeenAt` from services list is snapshot state, not a live heartbeat — state this in output

**Instrumentation Quality Rules (A1–A5):**

A1: Code reading is allowed and expected — reading source files is how you gather evidence.
A2: Label all findings with their evidence source: "source: tsuga CLI" or "source: code analysis".
A3: Refactor proposals require explicit user confirmation before writing code.
A4: Validate your understanding of existing instrumentation before concluding anything is missing.
A5: Distinguish advisory findings (suspected issues) from verified findings (confirmed via CLI data).
