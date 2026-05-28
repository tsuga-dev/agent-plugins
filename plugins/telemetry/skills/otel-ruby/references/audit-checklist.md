# Audit Checklist — Ruby OTel

> Last verified: 2026-03-23 | SDK: opentelemetry-sdk 1.10.0 / opentelemetry-exporter-otlp 0.32.0

## Signs OTel Is Already Set Up

Look for these indicators before adding instrumentation:

- `require 'opentelemetry/sdk'` in any Ruby file (initializer, config.ru, app.rb)
- `OpenTelemetry::SDK.configure` block
- `opentelemetry-sdk` or `opentelemetry-api` in the `Gemfile` or `Gemfile.lock`
- `OTEL_SERVICE_NAME` or `OTEL_EXPORTER_OTLP_ENDPOINT` in environment config / `.env`
- `opentelemetry-instrumentation-all` or individual `opentelemetry-instrumentation-*` gems

## Dependency Check

```bash
bundle exec gem list | grep opentelemetry
```

Expected minimum versions:

| Gem | Minimum |
|---|---|
| `opentelemetry-sdk` | >= 1.10.0 |
| `opentelemetry-exporter-otlp` | >= 0.32.0 |
| `opentelemetry-instrumentation-all` | latest |

Check that `opentelemetry-exporter-otlp` is present — without it, the `configure` block silently falls back to a noop exporter.

## Anti-Patterns to Flag

**1. `configure` called after first tracer call**

```ruby
# WRONG — tracer already obtained before SDK is configured
tracer = OpenTelemetry.tracer_provider.tracer('my-service')

OpenTelemetry::SDK.configure do |c|
  c.use_all
  # This configure is a no-op — SDK already locked in as noop
end

# CORRECT — configure first, get tracer after
# (service.name is read from OTEL_SERVICE_NAME env var — do not set c.service_name in code)
OpenTelemetry::SDK.configure do |c|
  c.use_all
end

tracer = OpenTelemetry.tracer_provider.tracer('my-service')
```

**2. Missing `require` for exporter before `configure`**

```ruby
# WRONG — configure block can't find OTLP exporter
require 'opentelemetry/sdk'
require 'opentelemetry/instrumentation/all'
# Missing: require 'opentelemetry/exporter/otlp'

OpenTelemetry::SDK.configure { |c| c.use_all }
# Exporter defaults to noop — no data sent

# CORRECT
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'        # REQUIRED before configure
require 'opentelemetry/instrumentation/all'
OpenTelemetry::SDK.configure { |c| c.use_all }
```

**3. Missing `c.use_all` or individual `c.use`**

Without `c.use_all` or explicit `c.use` calls, no auto-instrumentation is enabled:

```ruby
OpenTelemetry::SDK.configure do |c|
  # No c.use or c.use_all — only manual spans will work
end
```

**4. `configure` called in a Rake task without TracerProvider**

Rake tasks run in a different process context. If OTel is initialized only in Rails initializers, Rake tasks won't have it configured. Add to `lib/tasks/` or a standalone require:

```ruby
# Rakefile or task file
require_relative 'config/initializers/opentelemetry'
```

**5. Missing `deployment.environment.name`**

```ruby
# BAD — hardcoded from Rails.env in code; cannot change without a deploy
c.resource = OpenTelemetry::SDK::Resources::Resource.create(
  'deployment.environment.name' => Rails.env
)

# GOOD — set via env var; can be changed per environment without code change
# OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production
# Then in configure block — no deployment.environment.name in code at all:
OpenTelemetry::SDK.configure do |c|
  c.use_all
end
```

**6. gRPC protocol mismatch**

The default exporter uses HTTP/protobuf on port 4318. Setting `OTEL_EXPORTER_OTLP_PROTOCOL=grpc` without changing the endpoint to port 4317 causes silent failures:

```bash
# WRONG
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
# (4317 is correct for gRPC — this is actually OK)

# WRONG — HTTP port with gRPC protocol
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_EXPORTER_OTLP_PROTOCOL=grpc

# DEFAULT (no env vars needed for HTTP)
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318  # HTTP/protobuf default
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
1. Verify `OTEL_EXPORTER_OTLP_ENDPOINT` points to a reachable endpoint
2. Check `OTEL_EXPORTER_OTLP_PROTOCOL` matches the port (4318 for HTTP, 4317 for gRPC)
3. Confirm `require 'opentelemetry/exporter/otlp'` is before `configure`
4. Add `OTEL_LOG_LEVEL=debug` to see exporter output
5. In Rails, confirm the initializer runs before the first request (check load order)

## 11-Step Live Audit Workflow

Run these steps in order against a running service. Cite evidence for each finding.

**Step 1 — Confirm signals are arriving**

```bash
tsuga spans search --query "context.service.name:<service>" --max-results 5
tsuga logs search --query "context.service.name:<service> trace_id:*" --max-results 3
tsuga metrics list --filter "service.name=<service>"
```

Evidence required: output from each command or explicit "0 results" finding.

**Step 2 — Check resource attributes**

```bash
tsuga spans search --query "context.service.name:<service>" --max-results 1
# Inspect: service.version, deployment.environment.name present?
```

**Step 3 — Check service name source (env var vs hardcoded)**

```bash
kubectl exec -n <ns> <pod> -- env | grep OTEL_SERVICE_NAME
# or: docker inspect <container> | grep OTEL_SERVICE_NAME
```

Expected: `OTEL_SERVICE_NAME=<service>` — not hardcoded in the configure block.

**Step 4 — Check gem versions**

```bash
bundle exec gem list | grep opentelemetry
# Verify: opentelemetry-sdk >= 1.10.0, opentelemetry-exporter-otlp >= 0.32.0
```

**Step 5 — Check require order and configure placement**

```bash
grep -rn "opentelemetry" config/initializers/
grep -rn "OpenTelemetry::SDK.configure" config/
# Verify: require 'opentelemetry/exporter/otlp' appears before configure block
# Verify: configure block runs before first tracer_provider.tracer() call
```

**Step 6 — Check span naming quality**

```bash
tsuga spans search --query "context.service.name:<service>" --max-results 20
# Look for: string-interpolated paths (/users/42), camelCase names (processOrder), missing verb-object pattern
```

**Step 7 — Check span status correctness**

```bash
tsuga spans search --query "context.service.name:<service> status:ERROR" --max-results 10
# Verify: ERROR spans have a description; SERVER 4xx spans are UNSET not ERROR
```

**Step 8 — Check metric naming**

```bash
tsuga metrics list --filter "service.name=<service>"
# Look for: underscore names (http_requests), units in name (_ms, _bytes), service name as prefix
```

If source code path is available, also check instrument type:
- Description containing "current", "active", "open", "in-flight", or "pending" → must use UpDownCounter (not Counter)
- Description containing "duration", "latency", "time", or "size" → must use Histogram (not Counter or Gauge)

**Step 9 — Check log-trace correlation**

```bash
tsuga logs search --query "context.service.name:<service> trace_id:*" --max-results 5
# Verify: trace_id field present on log records; span_id present
```

**Step 10 — Check shutdown configuration (code review)**

```bash
grep -rn "tracer_provider.shutdown" config/ app/
# Verify: shutdown called in at_exit, Puma on_worker_shutdown, or Sidekiq config.on(:shutdown)
# Missing shutdown = most common cause of missing last batch of spans
```

**Step 11 — Check exporter configuration**

```bash
kubectl exec -n <ns> <pod> -- env | grep OTEL_EXPORTER
```

Expected:
- `OTEL_EXPORTER_OTLP_ENDPOINT` set (no endpoint hardcoded in configure block)
- `OTEL_EXPORTER_OTLP_PROTOCOL` absent (HTTP default) or `grpc` with port 4317

## Evidence Requirements

Each audit finding must include:
- **Command used** (CLI command or grep)
- **File path + line number** (for code findings)
- **Observed value** (what was found)
- **Expected value** (what it should be)

## Output Template

```
## Audit: <service-name> — <date>

### Signals Present
- Traces: [yes/no] — tsuga spans search returned N results
- Logs: [yes/no] — tsuga logs search returned N results
- Metrics: [yes/no] — tsuga metrics list returned N entries

### Resource Attributes
- service.name: [value] — source: [env var / hardcoded]
- service.version: [value or MISSING]
- deployment.environment.name: [value or MISSING]

### Findings
1. [Finding] — Evidence: [command + output]
   Fix: [specific action]

### Version Check
- opentelemetry-sdk: [version]
- opentelemetry-exporter-otlp: [version]
- Shutdown configured: [yes/no — where]
```

## Instrumentation Quality Rules

**A1 — Every service boundary has a span.** Each inbound HTTP/Rack handler and each outbound call must produce a span. No gaps at service edges.

**A2 — Span names are low-cardinality.** No user IDs, request IDs, or interpolated URL paths in span names. Use `{verb} {template}` pattern.

**A3 — Error spans have descriptions.** Every span with `Status.error(...)` must have a non-empty description string.

**A4 — Resource attributes are externally configurable.** `service.name`, `service.version`, and `deployment.environment.name` must be settable via env vars without a code change.

**A5 — No orphan spans.** Every span except root must have a parent. Scheduled jobs and queue consumers must create a root span, not inherit an unrelated parent.
