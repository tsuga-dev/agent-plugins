# OTel Instrumentation — Routing Decision Table

Use this table to determine which skill(s) to activate based on project context.

## Primary Routing: Language → Skill

| Detected Language / Runtime | Route To |
|----------------------------|----------|
| Go | `otel-go` |
| Python | `otel-python` |
| Java / Kotlin / Scala (JVM) | `otel-java` |
| Node.js / TypeScript | `otel-nodejs` |
| .NET / C# | `otel-dotnet` |
| Ruby / Rails | `otel-ruby` |
| Rust | `otel-rust` |
| PHP / Laravel / Symfony | `otel-php` |
| C++ | `otel-cpp` |
| Multiple languages (polyglot) | Route to each per-language skill; apply `references/k8s-deployment.md` for shared infra |
| Language unclear | Ask: "What language or runtime is this service written in?" |

## Secondary Routing: Task → Skill

| Task | Route To |
|------|----------|
| "Generate the code for me" | Handle inline (code generation path in this skill) |
| "Configure the Collector" | `otel-collector` |
| "Write OTTL / redact data in pipeline" | `otel-ottl` |
| "What should I name this attribute?" | `otel-semantic-conventions` |
| "Should this be a metric or span?" | `signal-choice-advisor` |
| "Audit instrumentation code" | `otel-<lang>` → `references/audit-checklist.md` |
| "Audit live metric signal quality" | `tsuga-audit-metrics` |
| "Audit live log signal quality" | `tsuga-audit-logs` |
| "Audit live trace signal quality" | `tsuga-audit-traces` |
| "No data showing up" | `tsuga-debug-no-data` |
| "Trace context not propagating" | `tsuga-debug-missing-trace-propagation` |

## Deployment Context Signals

Read these to supplement routing:

| Signal Found | Implication |
|-------------|-------------|
| `Dockerfile` / `docker-compose.yml` | Container deployment; check `OTEL_EXPORTER_OTLP_ENDPOINT` points to Collector |
| `k8s/`, `kubernetes/`, `*.yaml` with `kind: Deployment` | Kubernetes; load `references/k8s-deployment.md` for pod spec |
| `serverless.yml`, `template.yaml` (SAM), `*.tf` with Lambda | Serverless; OTLP HTTP preferred; cold start latency matters |
| `package.json` | Node.js; check for `@opentelemetry/` dependencies |
| `go.mod` | Go; check for `go.opentelemetry.io/otel` dependencies |
| `pom.xml` / `build.gradle` | Java; check for `opentelemetry-bom` |
| `requirements.txt` / `pyproject.toml` | Python; check for `opentelemetry-*` packages |
| `Gemfile` | Ruby; check for `opentelemetry-*` gems |
| `Cargo.toml` | Rust; check for `opentelemetry` crates |
| `composer.json` | PHP; check for `open-telemetry/api` |

## Signal Scope in Routing Instructions

When routing to a per-language skill, always include the signal scope in the instruction so the
language skill knows which sections are mandatory. Use this template:

> Route to `otel-<lang>`. Required signals: traces ✓  logs ✓  metrics ✓. Implement ALL listed
> signals before returning.

**Scope keywords — quick reference:**

| Task phrase | Implied scope |
|---|---|
| "add OTel", "instrument this service", "set up observability" (generic) | All three |
| "add tracing" / "set up spans" | Traces only |
| "add logging" / "set up log bridge" | Logs only |
| "add metrics" / "add a counter" | Metrics only |
| "add tracing and logging" | Traces + Logs |
| "add tracing and metrics" | Traces + Metrics |
| "traces, logs, and metrics" | All three |

When in doubt, default to all three.

## How to Detect Existing OTel Setup

Before generating any new setup, check:

1. Search for `TracerProvider`, `MeterProvider`, `LoggerProvider` in source files
2. Search for `OTEL_` in environment config files, Dockerfile, k8s manifests
3. Check dependency manifests for OTel packages (see table above)

If existing setup found: **do not duplicate**. Audit the existing setup against the per-language skill checklist instead.
