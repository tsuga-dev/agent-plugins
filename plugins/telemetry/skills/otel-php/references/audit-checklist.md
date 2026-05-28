# Audit Checklist — PHP OTel

> **Last verified:** 2026-03-23 | SDK: `open-telemetry/opentelemetry-php` 1.x

## Signs OTel Is Already Set Up

Look for these indicators before adding instrumentation:

- `use OpenTelemetry\API\Globals;` in any PHP file
- `TracerProvider` initialization in `bootstrap.php`, `index.php`, or a service provider
- `open-telemetry/sdk` or `open-telemetry/api` in `composer.json`
- `buildAndRegisterGlobal()` call somewhere in bootstrap code
- `OTEL_SERVICE_NAME` environment variable in `.env` or deployment config
- `open-telemetry/opentelemetry-auto-*` packages in `composer.json`
- `extension=opentelemetry.so` in `php.ini` (indicates C extension installed)

## Dependency Check

```bash
composer show | grep open-telemetry
```

Expected minimum versions:

| Package | Minimum version |
|---------|----------------|
| `open-telemetry/api` | 1.x |
| `open-telemetry/sdk` | 1.x |
| `open-telemetry/exporter-otlp` | 1.x |
| `php-http/guzzle7-adapter` | any (PSR-18 adapter required for HTTP export) |

Verify `php-http/guzzle7-adapter` is present — without it, `OtlpHttpTransportFactory` throws `HttpClientNotFoundException` at runtime.

Check the C extension is installed:

```bash
php -m | grep opentelemetry
# Expected: opentelemetry (required for auto-instrumentation to work)
```

## Anti-Patterns to Flag

**1. Missing `$scope->detach()` in `finally`**

```php
// WRONG — scope not detached; context stack corrupted for all subsequent code
$span  = $tracer->spanBuilder('op')->startSpan();
$scope = $span->activate();
try {
    doWork();
} finally {
    // Missing: $scope->detach();
    $span->end();
}

// CORRECT
} finally {
    $scope->detach();  // restore context FIRST
    $span->end();      // then end span
}
```

**2. `$span->end()` outside `finally`**

```php
// WRONG — end() not reached on exception
$span  = $tracer->spanBuilder('op')->startSpan();
$scope = $span->activate();
doWork();          // may throw
$scope->detach();  // never reached on exception
$span->end();      // never reached on exception — span leaks

// CORRECT — end() in finally
try {
    doWork();
} finally {
    $scope->detach();
    $span->end();
}
```

**3. No shutdown in long-running processes**

PHP-FPM terminates each request process, but long-running CLI scripts (queue workers, daemons) need explicit shutdown:

```php
// WRONG — spans buffered in BatchSpanProcessor are lost on process exit
Sdk::builder()->buildAndRegisterGlobal();  // no setAutoShutdown(true)

// CORRECT — setAutoShutdown registers a PHP shutdown function
Sdk::builder()->setAutoShutdown(true)->buildAndRegisterGlobal();
```

**4. `buildAndRegisterGlobal()` called after first `getTracer()`**

```php
// WRONG — tracer already obtained with noop provider
$tracer = Globals::tracerProvider()->getTracer('my-service');

// ... later in middleware/service provider ...
Sdk::builder()->buildAndRegisterGlobal();  // too late; no effect on existing tracers

// CORRECT — buildAndRegisterGlobal() before any getTracer() call
Sdk::builder()->setTracerProvider($tracerProvider)->buildAndRegisterGlobal();
$tracer = Globals::tracerProvider()->getTracer('my-service');
```

**5. Hardcoded `service.name` without env var fallback**

```php
// WRONG — service name baked into code; can't change without deploy
$resource = ResourceInfo::create(Attributes::create([
    ResourceAttributes::SERVICE_NAME => 'my-service',
]));

// CORRECT — ResourceInfoFactory::defaultResource() reads OTEL_SERVICE_NAME automatically
$resource = ResourceInfoFactory::defaultResource();
```

**6. `deployment.environment` (deprecated key)**

```php
// WRONG — deprecated semconv key (pre-1.27.0)
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production

// CORRECT — use deployment.environment.name (semconv 1.27.0+)
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production
```

**7. Consumer span using `setParent()` instead of span Link**

```php
// WRONG — makes consumer appear as child of producer HTTP request
$span = $tracer->spanBuilder('process order')
    ->setParent($extractedProducerContext)
    ->startSpan();

// CORRECT — new root linked to producer via addLink()
$span = $tracer->spanBuilder('process order')
    ->setNoParent()
    ->addLink(Span::fromContext($extractedProducerContext)->getContext())
    ->setSpanKind(SpanKind::KIND_CONSUMER)
    ->startSpan();
```

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

Expected: `OTEL_SERVICE_NAME=<service>` — not hardcoded in `ResourceInfo::create()`.

**Step 4 — Check Composer package versions**

```bash
composer show | grep open-telemetry
```

All packages should be at `1.x`. Confirm `php-http/guzzle7-adapter` is present.

**Step 5 — Check C extension is installed**

```bash
php -m | grep opentelemetry
# Expected: opentelemetry
# If absent and auto-instrumentation packages are installed, they will not work
```

**Step 6 — Check span naming quality**

```bash
tsuga spans search --query "context.service.name:<service>" --max-results 20
# Look for: raw paths (/users/123), camelCase names (processOrder), missing verb-object pattern
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

**Step 10 — Check scope management (code review)**

```bash
# Verify every activate() result is used with detach() in finally
grep -rn "->activate()" src/
# Each result should have a corresponding $scope->detach() in the same try/finally block

grep -rn "->end()" src/
# Each span->end() should be inside a finally block
```

**Step 11 — Check exporter configuration**

```bash
kubectl exec -n <ns> <pod> -- env | grep OTEL_EXPORTER
```

Expected:
- `OTEL_EXPORTER_OTLP_ENDPOINT` set (not hardcoded in `OtlpHttpTransportFactory::create()`)
- Protocol matches port (4318 for HTTP/protobuf, 4317 for gRPC)

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

### Extension
- ext-opentelemetry: [installed / not installed]

### Findings
1. [Finding] — Evidence: [command + output]
   Fix: [specific action]

### Version Check
- open-telemetry/sdk: [version]
- open-telemetry/api: [version]
- php-http/guzzle7-adapter: [present / missing]
```

## Instrumentation Quality Rules

**A1 — Every service boundary has a span.** Each inbound HTTP/gRPC handler and each outbound call must produce a span. No gaps at service edges.

**A2 — Span names are low-cardinality.** No user IDs, request IDs, or raw URL paths in span names. Use `{verb} {template}` pattern.

**A3 — Error spans have descriptions.** Every span with `StatusCode::STATUS_ERROR` must have a non-empty description string.

**A4 — Resource attributes are externally configurable.** `service.name`, `service.version`, and `deployment.environment.name` must be settable via env vars without a code change.

**A5 — No orphan spans.** Every span except root must have a parent. Scheduled jobs and queue consumers must create a root span (or use span Links), not inherit an unrelated parent.
