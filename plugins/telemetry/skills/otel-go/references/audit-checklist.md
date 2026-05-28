# Audit Checklist — Go OTel

> This file covers two audit modes:
> 1. **Code anti-patterns** (static) — section "Anti-Patterns to Flag"
> 2. **Cross-signal live audit** (tsuga CLI) — section "Cross-Signal Audit Workflow"
>
> For resource attribute auditing specifically, see `references/resource-attributes.md`.

---

## Signs OTel Is Already Set Up

Look for these indicators before adding instrumentation:

- `go.opentelemetry.io/otel` in `go.mod`
- `otel.SetTracerProvider(...)` or `otel.SetMeterProvider(...)` calls in main or init
- `tracer.Start(ctx, ...)` patterns in handlers
- `otlptracegrpc.New(...)` or `otlptracegrpc.New(...)` exporter setup
- `OTEL_SERVICE_NAME` or `OTEL_EXPORTER_OTLP_ENDPOINT` in environment config

## Dependency Check

```bash
go list -m go.opentelemetry.io/otel
go list -m go.opentelemetry.io/otel/sdk
go list -m go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc
```

Expected minimum versions:

| Module | Minimum |
|---|---|
| `go.opentelemetry.io/otel` | v1.x (latest stable) |
| `go.opentelemetry.io/otel/sdk` | v1.x (latest stable) |
| `go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc` | v1.x |
| `go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc` | v1.x |

Check for module version consistency — `otel`, `otel/sdk`, and `otel/exporters` packages should use the same major version.

## Anti-Patterns to Flag

**1. `span.End()` without `defer`**

```go
// WRONG — exception/panic or early return skips span.End()
ctx, span := tracer.Start(ctx, "op.name")
doWork(ctx)
span.End()  // not reached on panic or early return

// CORRECT
ctx, span := tracer.Start(ctx, "op.name")
defer span.End()
```

**2. Dropping `ctx` across goroutines**

```go
// WRONG — goroutine loses trace context
go func() {
    doWork(context.Background())  // broken trace linkage
}()

// CORRECT
go func(ctx context.Context) {
    ctx, span := tracer.Start(ctx, "background.task")
    defer span.End()
    doWork(ctx)
}(ctx)
```

**3. Missing `SetMeterProvider`**

Creating a `MeterProvider` but not setting it as global:

```go
// WRONG — metrics calls use noop global provider
mp := sdkmetric.NewMeterProvider(...)
// forgot: otel.SetMeterProvider(mp)

// CORRECT
otel.SetMeterProvider(mp)
```

**4. Using `context.Background()` in HTTP handlers**

```go
// WRONG — creates root span disconnected from incoming trace
func handler(w http.ResponseWriter, r *http.Request) {
    ctx, span := tracer.Start(context.Background(), "op")  // loses parent
    ...
}

// CORRECT — use request context which has parent span from middleware
func handler(w http.ResponseWriter, r *http.Request) {
    ctx, span := tracer.Start(r.Context(), "op")
    ...
}
```

**5. No `Shutdown()` call**

```go
// WRONG — in-flight spans are dropped on exit
func main() {
    setupOTel(ctx)
    runServer()
    // no shutdown
}

// CORRECT
func main() {
    shutdown, _ := setupOTel(ctx)
    defer shutdown(ctx)  // or signal handler
    runServer()
}
```

**6. gRPC endpoint with `http://` prefix**

```go
// WRONG — gRPC does not accept URL scheme
otlptracegrpc.WithEndpoint("http://localhost:4317")

// CORRECT
otlptracegrpc.WithEndpoint("localhost:4317")
otlptracegrpc.WithInsecure()
```

**7. Missing `deployment.environment.name`**

Tsuga filters by this attribute. Set it in the resource:

```go
semconv.DeploymentEnvironmentName("production")
```

or via:

```bash
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production
```

## Tsuga Verification Commands

After setup or audit:

```bash
# Check for traces
tsuga spans search --query "context.service.name:<your-service>" --max-results 5

# Check for log-trace correlation
tsuga logs search --query "context.service.name:<your-service> trace_id:*" --max-results 3

# Check for metrics
tsuga metrics list --filter "service.name=<your-service>"
```

If no spans appear:
1. Check `OTEL_EXPORTER_OTLP_ENDPOINT` — for gRPC, do not include `http://`
2. Verify the collector is reachable: `grpc_cli ls localhost:4317`
3. Confirm `otel.SetTracerProvider(tp)` is called before any `otel.Tracer()` calls
4. Add `sdktrace.WithSyncer(exporter)` temporarily during debugging for synchronous export

---

## Cross-Signal Audit Workflow

Use when asked: "Audit the instrumentation", "Full observability review", "Check telemetry completeness", "Is this service fully instrumented?"

**Required input:** service name (ask if missing). Source code path is optional; enables SDK init checks.

### Step 1 — Locate service and check signal presence

```bash
tsuga services list
tsuga services get <id>
```

Capture `sources[]`, `logsCount24h`, `tracesCount24h`, `errorLogsCount24h`, `errorTracesCount24h`.

Classify:
- No signals at all → stop; direct to `otel-instrumentation`
- Logs only / Traces only / Metrics only → note what's missing; continue what's present
- All 3 present → continue full audit

### Step 2 — Cross-signal correlation check

```bash
tsuga logs search --query "context.service.name:<name> trace_id:*" --max-results 3
```

`trace_id` absent = high-impact gap. Note: "source: tsuga CLI, command: `tsuga logs search ...`"

### Step 3 — Metric naming spot-check

```bash
tsuga metrics list --filter "service.name=<name>"
```

Spot-check up to 3 metric names for violations: dot notation, no service prefix, no units in name, no env prefix. Cite metric name + rule violated.

### Step 4 — Log structure check

```bash
tsuga logs search --query "context.service.name:<name>" --max-results 5
```

Check: structured fields present (not a single blob message); `trace_id` is a top-level field.

### Step 5 — Trace resource identity check

```bash
tsuga spans search --query "context.service.name:<name>" --max-results 5
```

Check `resourceAttributes` for `service.name` and `service.version`. See `references/resource-attributes.md` for full resource audit.

### Step 6 — Span status correctness

In sampled spans: SERVER spans with 4xx status should have UNSET status (not ERROR). CLIENT spans with 4xx should have ERROR. Flag any violations.

### Step 7 — Span naming patterns

Check for: raw IDs in span names, missing verb-object format. Examples: `"GET /users/123"` → BAD; `"GET /users/{id}"` → GOOD.

### Step 8 — Cardinality check

In sampled metric attributes: flag `user.id`, `request.id`, raw URL paths, trace IDs. These must not appear in metric dimensions.

### Step 9 — Quality report

```bash
tsuga quality-reports list
```

Note `generatedAt` — flag as stale if > 48h ago. Note rule failures attributed to this service.

### Step 10 — Source code check (if path provided)

Read SDK init file. Check for:
- `TracerProvider`, `MeterProvider`, `LoggerProvider` initialization
- Log bridge setup (`otelslog.NewHandler` or `otelzap.NewCore`)
- Resource attributes set at init (`service.name`, `service.version`, `deployment.environment.name`)
- Exporter endpoint: **fail** if hardcoded (`WithEndpoint("http://localhost:4317")` in code); **pass** if zero-arg constructor AND `OTEL_EXPORTER_OTLP_ENDPOINT` is in deployment config

If metric creation code is available, check instrument type:
- Description containing "current", "active", "open", "in-flight", or "pending" → must use `UpDownCounter` (not `Counter`)
- Description containing "duration", "latency", "time", or "size" → must use `Histogram` (not `Counter` or `Gauge`)

### Step 11 — Validate with user

> "Here's what I found across all three signals — [summary]. Does this match how instrumentation is set up? Anything I should know before I finalize findings?"

Adjust based on response.

---

## Evidence Requirements

- Signal presence = `sources[]` and 24h counters from `tsuga services get`; label "source: tsuga CLI"
- Correlation finding = `tsuga logs search` result with/without `trace_id` field
- Metric naming finding = cite exact metric name + rule violated
- Resource identity finding = cite `resourceAttributes` from spans search
- Source code finding = cite file path + line; label "source: code analysis"
- **Advisory vs verified:** distinguish suspected issues (code analysis) from confirmed findings (CLI data)

---

## Output Template

```
## Instrumentation Audit: <service>

## Signal Coverage
| Signal                | Status                                         | 24h Count |
|-----------------------|------------------------------------------------|-----------|
| Metrics               | ✅ Present / ❌ Missing / ⚠️ Sparse (<10/24h)   | <N>       |
| Traces                | ✅ Present / ❌ Missing                          | <N>       |
| Logs                  | ✅ Present / ❌ Missing                          | <N>       |
| Trace-log correlation | ✅ Working / ❌ Missing / ⚠️ Not tested          | trace_id in logs: yes/no |

## Cross-Signal Summary
<1-3 sentences: what is working, what is the biggest gap>

## Findings (prioritized)

### Critical
- <finding + evidence source>

### High
- <finding + evidence source>

### Medium
- <finding + evidence source>

## Resource Identity (from traces)
service.name: <present/MISSING> | service.version: <present/MISSING>

## Exporter Configuration
Endpoint hardcoded: ✅ no / ❌ yes (file:line) | OTEL_EXPORTER_OTLP_ENDPOINT configured: ✅ / ❌ / ⚠️ not checked

## Quality Report
<N rule failures / No failures / ⚠️ Report stale — generated: <generatedAt>>

## Recommended Actions (in order of impact)
1. <highest-impact fix> — run `<specific skill>` for detailed guidance
2. ...

## Limitations
- Condensed audit: 5-record samples per signal; use tsuga-audit-metrics / tsuga-audit-logs / tsuga-audit-traces for full per-signal analysis
- Metric check covers spot-check of up to 3 metric names only
- Source code findings (if any) are from the provided path only
- Quality report reflects state at generatedAt, not live state
```

---

## Instrumentation Quality Rules (A1–A5)

A1: Code reading is allowed and expected — reading source files is how you gather evidence.
A2: Label all findings with their evidence source: "source: tsuga CLI" or "source: code analysis".
A3: Refactor proposals require explicit user confirmation before writing code.
A4: Validate your understanding of existing instrumentation before concluding anything is missing.
A5: Distinguish advisory findings (suspected issues) from verified findings (confirmed via CLI data).

---

## Safety Rules

- Advisory only — this audit proposes actions; it does not apply changes
- Do not reproduce raw log or span attribute values; inspect field names only
- If `context.sensitive == "true"` appears in any record: stop field-level inspection for that service
- Never read `.env`, `*.secret`, `*credentials*`, `*token*` files during source inspection
