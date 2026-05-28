---
name: otel-instrumentation
description: "Use for any OpenTelemetry request when language is unknown or the task is broad — 'add OTel', 'instrument this service', 'audit observability', 'inject trace_id into logs', 'fix service.name', 'instrument Kafka'. Also use when the user asks to generate SDK setup code."
---

# OTel Instrumentation — Entry, Router & Code Generator

> **Last verified:** 2026-03-22

This is the entry skill for OpenTelemetry instrumentation. Its job is to infer project context and route to the right specialist skill — or generate SDK setup code when the user explicitly requests it.

## When to Use This Skill

- Language is unknown or ambiguous: "add OTel", "set up observability", "instrument this service"
- User wants code generated: "write the setup", "generate the boilerplate", "bootstrap OTel for me"
- Audit request with unknown language: "audit service X", "is this service fully instrumented?", "full observability review"
- Log correlation request: "add trace-log correlation", "inject trace_id into logs", "why isn't trace_id in my logs?"
- Resource attribute request: "check resource attributes", "fix missing service.name", "update deployment.environment"
- Async messaging request: "instrument Kafka", "context lost in message queue", "trace across SQS"

**If the language is already confirmed:** go directly to `otel-<lang>` — skip this skill.

## Quick Route — Specific Tasks

When the user's intent is specific (not a full setup), infer the language and route directly to the per-language reference file:

| Intent | Route to |
|--------|----------|
| Audit cross-signal quality / full observability review | `otel-<lang>` → `references/audit-checklist.md` |
| Add trace-log correlation / inject trace_id | `otel-<lang>` → `references/logs.md` |
| Check / fix resource attributes / `service.name` is `unknown_service` | `otel-<lang>` → `references/resource-attributes.md` |
| Instrument Kafka / SQS / RabbitMQ / message queue | `otel-<lang>` → `references/async-messaging.md` |
| Add metrics instrumentation | `otel-<lang>` → `references/metrics.md` |
| Add span instrumentation | `otel-<lang>` → `references/spans.md` |
| Redact PII / sensitive data from spans or logs | `otel-ottl` |
| Service is slow / high latency / p95 spikes | `tsuga-analyze-trace-latency` |

For all these cases: if language is unknown, infer it from the codebase (imports, manifest files) before routing. If still ambiguous, ask.

## Required Inputs (for code generation path)

- **Language/runtime** (required — ask if missing; this skill library covers: C++, .NET, Go, Java, JavaScript/Node.js, PHP, Python, Ruby, Rust. Note: Swift, Erlang/Elixir, and Kotlin are also official OTel SDK languages but are not yet covered by this skill library.)
- **Service name** (required — used in resource attributes in generated code)
- **Service type** (optional: HTTP API / background worker / CLI — affects auto-instrumentation recommendations)
- **Source code path** (optional — if provided, check what already exists before generating)

## Workflow

### Advisory / Routing Path

1. **Infer context** — check for: language/runtime, framework, deployment environment
   (k8s, serverless, bare metal), existing OTel setup.

2. **Extract signal scope** — parse the task description for signal keywords:

   | Keyword(s) | Signal required |
   |---|---|
   | traces / tracing / spans / distributed tracing | Traces |
   | logs to endpoint / OTLP logs / log export / logs must be sent to | Logs — **export** (requires LoggerProvider + OTLPLogExporter) |
   | trace IDs in logs / log correlation / log bridge / correlate logs | Logs — **correlation** (log bridge sufficient) |
   | logs / logging / structured logs (generic) | Logs — **export** (default to the more complete requirement) |
   | metrics / counters / histograms / gauges | Metrics |

   If the task says "instrument this service", "add OTel", "set up observability", or any other
   generic phrasing **without naming specific signals**: default to **all three** (traces + logs +
   metrics) as per OTel best practices.

   Before routing, produce a one-line scope statement:

   > **Signal scope:** traces ✓  logs ✓  metrics ✓

   Use `—` for signals not required. Example for a traces-only task:
   > **Signal scope:** traces ✓  logs —  metrics —

3. **Pre-flight: check for existing instrumentation** — for each signal marked ✓ in the scope,
   search the codebase (see full detection methods in `references/routing.md`):

   | Signal | Search terms (grep, language-specific) |
   |--------|----------------------------------------|
   | Traces | `TracerProvider`, `tracerProvider`, `NewTracerProvider`, `set_tracer_provider`, `SetTracerProvider`, `AddSource(`, `opentelemetry.trace` |
   | Metrics | `MeterProvider`, `meterProvider`, `NewMeterProvider`, `set_meter_provider`, `SetMeterProvider`, `AddMeter(`, `opentelemetry.metrics` |
   | Logs | `LoggerProvider`, `loggerProvider`, `OTLPLogExporter`, `LoggingHandler`, `LoggingInstrumentor`, `WithLogging(`, `OpenTelemetryTransportV3`, `pino-opentelemetry-transport`, `otelslog.NewHandler`, `otelzap`, `tracing_opentelemetry::layer` |

   **Java agent special case:** Also check for `opentelemetry-javaagent.jar` in Dockerfile,
   shell scripts, or JVM args. If found: all three signals are already active via the agent —
   mark all as "audit only"; do NOT generate a `TracerProvider`/`MeterProvider`/`LoggerProvider`
   (doing so creates duplicate providers that conflict with the agent).

   For each signal in scope:
   - **Not found** → mark as "implement from scratch"
   - **Found** → do NOT duplicate. Mark as "audit only" — note specifically what is missing
     (e.g. "LoggingInstrumentor present but no structured JSON output configured")

   If a source path was provided, prefer reading the entry point file (see Code Generation Path
   step CGP-2 for the per-language entry point list) over relying on grep terms alone — file reads
   give definitive results; grep can miss auto-instrumentation agents.

   Include a pre-flight report in the routing instruction:
   > Pre-flight — traces: not found (implement from scratch). logs: LoggingInstrumentor found,
   > no JSON formatter (add only). metrics: MeterProvider found (skip).

4. **Route to specialist** — see `references/routing.md`. Include signal scope AND pre-flight
   report in the routing instruction. Template:

   > Route to `otel-<lang>`. Required signals: <scope>. Pre-flight: <findings>. Implement only
   > what is missing per pre-flight findings. Return after all required signals are addressed.

5. **Completion gate** — after the language skill returns, verify that each signal marked ✓ in
   the scope was actually implemented:
   - Traces: TracerProvider initialized + at least one span created
   - Logs (export): LoggerProvider + OTLPLogExporter initialized AND exporting to the configured
     endpoint. A log bridge alone (LoggingInstrumentor, slog handler, MDC, etc.) does NOT satisfy
     this gate — it injects trace context but does not ship logs to the collector.
   - Logs (correlation): Log bridge initialized + trace_id/span_id present in log records.
     LoggerProvider is not required. (Rust: `tracing_opentelemetry::layer()` + `fmt::layer().json()` satisfies this.)
   - Metrics: MeterProvider initialized + at least one instrument created

   If any required signal is missing: state which signal is absent and route back to `otel-<lang>`
   with a focused instruction: "Implement <missing signal> — this was required per the original task
   scope." Repeat until all required signals are implemented or the user cancels.

---

### Code Generation Path (when user explicitly requests code)

These steps apply **only** when the user has explicitly asked for code to be generated
(e.g. "write the setup", "generate the boilerplate"). The Advisory/Routing path above handles all
other cases. Safety rules for this path are in the **Safety Rules** section below.

CGP-1. If service name provided: `tsuga services list` — check whether this service is already emitting signals. If yes: note which signals are present; adjust the output to focus on what is missing rather than generating a full setup.

CGP-2. If source path provided:
   - Read the dependency manifest for the detected language:
     - **Node.js:** `package.json`
     - **Python:** `requirements.txt` / `pyproject.toml`
     - **Go:** `go.mod`
     - **Java:** `pom.xml` / `build.gradle`
     - **.NET:** `*.csproj` (look for `<PackageReference Include="OpenTelemetry`)
     - **Ruby:** `Gemfile`
     - **Rust:** `Cargo.toml`
     - **PHP:** `composer.json`
     - **C++:** `CMakeLists.txt` / `conanfile.txt` / `vcpkg.json`
   - Read the top-level application entry point to check whether SDK is already initialized (TracerProvider, MeterProvider):
     - **Node.js:** `index.js` / `server.js` / `app.js`
     - **Python:** `app.py` / `main.py`
     - **Go:** `main.go`
     - **Java:** `Main.java` / `Application.java`
     - **.NET:** `Program.cs` / `Startup.cs`
     - **Ruby:** `app.rb` / `config.ru` / `application.rb`
     - **Rust:** `main.rs` / `lib.rs`
     - **PHP:** `index.php` / `app.php`
     - **C++:** `main.cpp`
   - If SDK init is already present: note it explicitly and generate only the missing pieces (e.g., missing log bridge, missing metrics setup).

CGP-3. **Confirm before generating.**

   Present the structure of what will be generated: language, service name, and which of the 4 sections (SDK Initialization, Auto-Instrumentation, Trace-Log Correlation, First Custom Metric) will be included. Ask: "Shall I generate the full setup code for \<service-name\>? (yes / no)". Generate only after confirmation.

   After deploy, recommend running `tsuga-smoke-test` to verify — do not block on it or treat it as a required step.

CGP-4. Generate setup in 4 sections (see output template). Read the authoritative language skill instead of generating inline code:

   | Language | Full setup guide |
   |---|---|
   | Python | `otel-python` → `references/quickstart.md` |
   | Go | `otel-go` → `references/quickstart.md` |
   | Java | `otel-java` → `references/quickstart.md` |
   | Node.js | `otel-nodejs` → `references/quickstart.md` |
   | .NET | `otel-dotnet` → `references/quickstart.md` |
   | Ruby | `otel-ruby` → `references/quickstart.md` |
   | Rust | `otel-rust` → `references/quickstart.md` |
   | PHP | `otel-php` → `references/quickstart.md` |
   | C++ | `otel-cpp` → `references/quickstart.md` |

CGP-5. After presenting the setup: note that the user should run `tsuga-smoke-test` for `<service-name>` after deploying to confirm all three signals are arriving.

## Rule Files

- [`references/routing.md`](references/routing.md) — Decision table: project context → which skill to load
- [`references/checklist.md`](references/checklist.md) — Well-instrumented service quick reference

## Output Template (code generation path)

```
## New Service O11y Setup: <service-name> (<language>)

[If service already exists in Tsuga:]
⚠️ Service already emitting signals: <list>. Generating setup for missing pieces only: <list>.

## 1. SDK Initialization
[Read the relevant language skill's `references/quickstart.md` (e.g., `otel-python/references/quickstart.md`) for the authoritative SDK init pattern for the detected language. Generated code MUST: (1) use zero-arg exporter constructors (no `endpoint=` arguments), (2) use the SDK's env-var-aware resource factory. For languages without a quickstart.md yet: generate based on official API docs following the same constraints.]

## 2. Auto-Instrumentation
<packages to install + initialization call for HTTP/DB/framework auto-instrumentation>
Covers: <list what gets auto-instrumented: HTTP server spans, DB client spans, etc.>
Not covered (add manually): <what requires manual spans for this service type>

## 3. Trace-Log Correlation
<minimal code to inject trace_id and span_id into log output>
Library: <detected or conventional logging library for this language>
Approach: <language-appropriate method — e.g., log bridge package (JS/Python), MDC (Java), ILogger integration (.NET), tracing crate bridge (Rust), manual context extraction (Go/Ruby/PHP/C++)>

## 4. First Custom Metric (example)
<one concrete Histogram example for the most common operation in this service type>
Note: See `signal-choice-advisor` for instrument type selection guidance.

## Verification
After deploying, run `tsuga-smoke-test` for <service-name> to confirm signals arrive.

## Limitations
- Generated for <language>; adapt to your specific framework if different from examples
- Auto-instrumentation packages may need version pinning — check OTel registry for latest stable versions
- Resource attributes shown here are the minimum required; add deployment.environment.name and host.name for full context
- Output is copy-paste only; this skill does not write to source files
```

## Safety Rules (code generation)

- Never write to source files — all output is copy-paste only
- If existing SDK initialization is found in source: note it explicitly; do not generate a duplicate. Show only the missing pieces.
- Do not hardcode ingestion keys or endpoint URLs in generated code — use environment variable placeholders (`process.env.TSUGA_INGESTION_KEY`, `os.environ["TSUGA_INGESTION_KEY"]`)
- **Never emit `endpoint=` or `setEndpoint(...)` in generated SDK init code.** Generated code must use zero-arg exporter constructors that auto-read `OTEL_EXPORTER_OTLP_ENDPOINT`. Show the env var in a separate configuration block, not in source code.
- **Never emit hardcoded resource attributes in generated code.** Generated SDK init must use the SDK's env-var-aware resource factory (`Resource.create({})`, `resource.WithFromEnv()`, `Resource.getDefault()`, etc.). Service name and version belong in `OTEL_SERVICE_NAME` and `OTEL_RESOURCE_ATTRIBUTES`, not in code.
- Never read `.env`, `*.secret`, `*credentials*`, or `*token*` files — flag and stop if encountered
- If the user's language is not one of the 9 languages covered by this skill library (C++, .NET, Go, Java, JavaScript/Node.js, PHP, Python, Ruby, Rust): state that this skill library does not yet cover that language and point the user to https://opentelemetry.io/docs/languages/ for official SDK documentation. Do not claim it is "not a supported OTel SDK language" — Swift, Erlang/Elixir, Kotlin, and others are official OTel languages.
- Generated code is illustrative — always note that the user should verify package versions and adapt to their specific framework
- Does not cover Collector configuration — use `otel-collector` for that
- Does not cover OTTL — use `otel-ottl` for pipeline transformations
