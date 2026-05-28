# Audit Checklist — Python OTel

## Signs OTel Is Already Set Up

Look for these indicators before adding instrumentation:

- `import opentelemetry` or `from opentelemetry import ...` in any Python file
- `TracerProvider()` or `MeterProvider()` initialization calls
- `.instrument()` calls (e.g., `FlaskInstrumentor().instrument()`)
- `opentelemetry-api` or `opentelemetry-sdk` in `requirements.txt` or `pyproject.toml`
- `opentelemetry-instrument` wrapper in Dockerfile or startup scripts
- `OTEL_SERVICE_NAME` environment variable in deployment config

## Dependency Check

```bash
pip show opentelemetry-api opentelemetry-sdk opentelemetry-exporter-otlp-proto-grpc
```

Expected minimum versions:

| Package | Minimum |
|---|---|
| `opentelemetry-api` | >= 1.40.0 |
| `opentelemetry-sdk` | >= 1.40.0 |
| `opentelemetry-exporter-otlp-proto-grpc` | >= 1.40.0 |
| `opentelemetry-instrumentation` | >= 0.61b0 |

Check that all `opentelemetry-*` packages use the same major version — mixing 1.35 and 1.40 causes `AttributeError` on newer API methods.

## Anti-Patterns to Flag

**1. Creating instrumented library instances before calling `.instrument()`**

```python
# WRONG — Flask app instantiated before FlaskInstrumentor replaces the class
from flask import Flask
app = Flask(__name__)  # uses original Flask class
from opentelemetry.instrumentation.flask import FlaskInstrumentor
FlaskInstrumentor().instrument()  # too late — app already created

# CORRECT — instrument before creating the Flask app instance
from opentelemetry.instrumentation.flask import FlaskInstrumentor
FlaskInstrumentor().instrument()
from flask import Flask  # importing Flask before instrument() is fine
app = Flask(__name__)    # uses patched Flask class

# ALSO CORRECT — instrument an existing app instance directly
from flask import Flask
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)
```

**2. Not using `start_as_current_span` as context manager**

```python
# WRONG — span not ended if exception occurs
span = tracer.start_span("op.name")
do_work()  # may raise
span.end()  # never reached on exception

# CORRECT
with tracer.start_as_current_span("op.name") as span:
    do_work()
# span.end() called automatically
```

**3. Using `print()` instead of logging**

`print()` statements are not captured by OTel's log bridge or structured logging systems. Use `logging.getLogger(__name__)` for all log output.

**4. No `MeterProvider` configured**

```python
# Metrics calls silently become no-ops if MeterProvider is not set
meter = metrics.get_meter("my-service")
counter = meter.create_counter("requests.total")
counter.add(1)  # no-op if MeterProvider is not set
```

Always call `metrics.set_meter_provider(meter_provider)` during initialization.

**5. Hardcoded `service.name`**

```python
# WRONG — cannot be changed at deploy time; no env var override path
resource = Resource.create({"service.name": "my-service"})

# CORRECT — Resource.create() (zero-arg) auto-merges OTEL_SERVICE_NAME and OTEL_RESOURCE_ATTRIBUTES
resource = Resource.create()
```

Set the service name via environment:

```bash
OTEL_SERVICE_NAME=my-service
```

**6. Missing `deployment.environment.name`**

```bash
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production
```

**7. `LoggingInstrumentor` called after logging is configured**

`logging.getLogger()` itself is not the problem — `LoggingInstrumentor` patches at the class level and applies to all loggers. The real issue is calling `instrument()` after `logging.basicConfig()` or any framework logging setup that sets handler formatters without OTel fields.

```python
# WRONG — basicConfig() locks in a formatter before instrumentation updates it
import logging
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
LoggingInstrumentor().instrument(set_logging_format=True)  # formatter already set

# CORRECT — instrument before any logging configuration
LoggingInstrumentor().instrument(set_logging_format=True)
import logging
logging.basicConfig(level=logging.INFO)
```

**8. No `tracer_provider.shutdown()` on exit**

For long-running services, register a shutdown handler:

```python
import atexit
atexit.register(tracer_provider.shutdown)
atexit.register(meter_provider.shutdown)
```

## Tsuga Verification Commands

```bash
# Check for traces
tsuga spans search --query "context.service.name:<your-service>" --max-results 5

# Check for log-trace correlation
tsuga logs search --query "context.service.name:<your-service> trace_id:*" --max-results 3

# Check for metrics
tsuga metrics list --filter "service.name=<your-service>"
```

If no spans appear:
1. Check `OTEL_EXPORTER_OTLP_ENDPOINT` — for gRPC use `http://host:4317` (not HTTPS unless TLS is configured)
2. Run with `OTEL_PYTHON_LOG_LEVEL=debug` for verbose exporter output (the Python SDK does not honor the spec-level `OTEL_LOG_LEVEL`)
3. Confirm `trace.set_tracer_provider(tracer_provider)` is called before any `trace.get_tracer()` calls
4. Try switching to `ConsoleSpanExporter` temporarily to verify spans are being created

---

## 11-Step Cross-Signal Audit Workflow

Use this workflow when auditing an existing service for instrumentation quality. All findings must cite CLI command + output or file:line as evidence.

### Step 1 — Signal presence

```bash
tsuga spans search --query "context.service.name:<service>" --max-results 5
tsuga metrics list --filter "service.name=<service>"
tsuga logs search --query "context.service.name:<service>" --max-results 5
```

Record which signals are present. Missing signals = P1 gap.

### Step 2 — Trace-log correlation

```bash
tsuga logs search --query "context.service.name:<service> trace_id:*" --max-results 3
```

If `trace_id` is absent from log records: check that `LoggingInstrumentor().instrument()` is called before `logging.basicConfig()` or any framework logging setup. See `references/logs.md`.

### Step 3 — Metric naming

```bash
tsuga metrics list --filter "service.name=<service>"
```

Flag any metric names with underscores, service-name prefixes, unit suffixes (`_ms`, `_bytes`), or environment prefixes (`prod_`, `staging_`). Check `references/otel-reference.md` naming rules.

If source code path is available, also check instrument type:
- Description containing "current", "active", "open", "in-flight", or "pending" → must use `UpDownCounter` (not `Counter`)
- Description containing "duration", "latency", "time", or "size" → must use `Histogram` (not `Counter` or `Gauge`)

### Step 4 — Log structure

```bash
tsuga logs search --query "context.service.name:<service>" --max-results 3
```

Confirm logs are structured JSON (not raw strings). Flag `print()` usage in source. Check `references/logs.md`.

### Step 5 — Trace resource identity

```bash
tsuga spans search --query "context.service.name:<service>" --max-results 1
```

Confirm `service.name`, `service.version`, `deployment.environment.name` are present. Flag missing or hardcoded values. Check `references/resource-attributes.md`.

### Step 6 — Span status correctness

Review spans for status errors. Check:
- SERVER spans: 4xx responses should be UNSET (not ERROR)
- CLIENT spans: 4xx responses should be ERROR
- Error spans: must have a status description message

```bash
tsuga spans search --query "context.service.name:<service> status:error" --max-results 10
```

### Step 7 — Span naming

```bash
tsuga spans search --query "context.service.name:<service>" --max-results 20
```

Flag spans with:
- Raw paths with IDs (e.g., `/users/123/orders`)
- camelCase names (`processOrder`)
- Underscores instead of spaces

### Step 8 — Cardinality check

`tsuga metrics list` shows metric names, not attribute keys on recorded data points. Cardinality must be checked in source code.

Search for high-cardinality patterns in metric recording calls:

```bash
# Look for .add() and .record() calls with suspicious attribute keys
grep -rn "\.add\(.*user_id\|\.add\(.*request_id\|\.add\(.*session\|\.record\(.*user_id" src/
grep -rn "\.add\(.*url\|\.add\(.*path\|\.record\(.*url" src/
```

Flag any `.add()` or `.record()` call that passes runtime-generated strings (user IDs, session tokens, full URLs, raw paths, request IDs) as attribute values.

### Step 9 — Quality report

```bash
tsuga spans search --query "context.service.name:<service> kind:INTERNAL" --max-results 20
```

Flag traces with > 10 INTERNAL spans (over-instrumentation). Flag CLIENT or PRODUCER spans with no parent (missing propagation).

### Step 10 — Source code check

Read the SDK initialization code:
- Confirm `Resource.create()` (zero-arg, preferred) or `Resource.create({...})` — not hardcoded `service.name`
- Confirm `LoggingInstrumentor().instrument()` called before `logging.basicConfig()` or framework logging setup
- Confirm `atexit.register(tracer_provider.shutdown)` registered
- Confirm `OTEL_METRICS_EXPORTER=otlp` is set (spec default is `otlp`, but Python SDK treats unset as `none`)

### Step 11 — Validation gate

Before marking audit complete, confirm:
- [ ] All three signals present in Tsuga
- [ ] Trace-log correlation working (`trace_id` in log records)
- [ ] No naming violations
- [ ] Resource attributes complete
- [ ] No `print()` statements used for logging
- [ ] Span statuses correct (4xx on SERVER = UNSET)

---

## Evidence requirements

All findings must cite:
- CLI command used + representative output, OR
- File path + line number

Do not state findings without traceable evidence.

---

## Output template

```
## Signal Coverage
| Signal | Present | Notes |
|--------|---------|-------|
| Traces | ✅/❌ | ... |
| Metrics | ✅/❌ | ... |
| Logs | ✅/❌ | ... |
| Trace-log correlation | ✅/❌ | ... |

## Findings (prioritized)
1. [P1] <finding> — evidence: <command> showed <output>
2. [P2] <finding> — evidence: <file>:<line>
...
```

---

## Instrumentation quality rules

**A1 — Signal completeness:** All three signals (traces, metrics, logs) must be present and arriving in Tsuga before audit passes.

**A2 — Correlation:** Every log record emitted inside a span must include `trace_id` and `span_id`.

**A3 — Resource identity:** `service.name`, `service.version`, and `deployment.environment.name` must be set on all signals.

**A4 — Naming:** No metric or span name may contain underscores, service-name prefixes, unit suffixes, or environment prefixes.

**A5 — Status correctness:** SERVER spans must not set ERROR for 4xx responses. All ERROR spans must include a status description.
