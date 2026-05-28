# Audit Checklist — Java OTel

## Signs OTel Is Already Set Up

Look for these indicators before adding instrumentation:

- `import io.opentelemetry` anywhere in Java source files
- `OpenTelemetrySdk.builder()` or `GlobalOpenTelemetry.getTracer(...)` calls
- `-javaagent:` flag in JVM startup scripts, Dockerfiles, or systemd unit files
- `opentelemetry-bom` in `pom.xml` or `build.gradle`
- `opentelemetry-javaagent.jar` present in the deployment directory or classpath
- `OTEL_SERVICE_NAME` environment variable set in deployment config

## Dependency Check

**Maven:**

```bash
mvn dependency:tree | grep opentelemetry
```

**Gradle:**

```bash
./gradlew dependencies | grep opentelemetry
```

Expected minimum versions:

| Artifact | Minimum version |
|---|---|
| `opentelemetry-bom` | 1.60.1 |
| `opentelemetry-javaagent` | 2.26.0 |
| `opentelemetry-instrumentation-annotations` | 2.26.0 |
| `opentelemetry-logback-mdc-1.0` | 2.26.0-alpha |

Check that instrumentation artifacts match the agent version — mixing agent 2.26.0 with instrumentation 2.20.0-alpha causes runtime errors.

## Anti-Patterns to Flag

**1. `span.end()` not in `finally`**

```java
// WRONG — exception skips span.end(), leaving span open forever
try (Scope scope = span.makeCurrent()) {
    doWork();
    span.end();  // not reached if doWork() throws
}

// CORRECT
try (Scope scope = span.makeCurrent()) {
    doWork();
} finally {
    span.end();
}
```

**2. Not closing `OpenTelemetrySdk`**

```java
// WRONG — no shutdown hook; last spans dropped on exit
OpenTelemetrySdk openTelemetry = OpenTelemetrySdk.builder()
    .buildAndRegisterGlobal();

// CORRECT
Runtime.getRuntime().addShutdownHook(new Thread(openTelemetry::close));
```

**3. Mixing agent + manual SDK without awareness**

When the Java agent is present, calling `OpenTelemetrySdk.builder().buildAndRegisterGlobal()` overrides the agent's registered `OpenTelemetry` instance. Use `GlobalOpenTelemetry.get()` to retrieve the agent-configured instance instead of creating a new one.

**4. Missing BOM in Maven/Gradle**

Without `opentelemetry-bom`, individual packages may resolve to incompatible versions. Always import the BOM in `dependencyManagement`.

**5. `span.makeCurrent()` Scope not closed**

```java
// WRONG — Scope is not auto-closed; context stack corrupted
Scope scope = span.makeCurrent();
doWork();
scope.close();   // if doWork() throws, scope.close() is never called

// CORRECT — try-with-resources
try (Scope scope = span.makeCurrent()) {
    doWork();
}
```

**6. Missing `deployment.environment.name`**

```bash
# CORRECT — set via env var
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production

# Or in programmatic init:
Resource.builder().put(DeploymentIncubatingAttributes.DEPLOYMENT_ENVIRONMENT_NAME, "production").build()
# NOTE: DEPLOYMENT_ENVIRONMENT_NAME is in the incubating package (opentelemetry-semconv-incubating)
```

**7. Agent version mismatch with instrumentation artifacts**

The `-alpha` instrumentation packages (e.g., `opentelemetry-logback-mdc-1.0`) must match the agent version exactly. Version 2.26.0-alpha must be used with agent v2.26.0.

## Tsuga Verification Commands

After setup or audit, verify signals are arriving:

```bash
# Check for traces
tsuga spans search --query "context.service.name:<your-service>" --max-results 5

# Check for log-trace correlation
tsuga logs search --query "context.service.name:<your-service> trace_id:*" --max-results 3

# Check for metrics
tsuga metrics list --filter "service.name=<your-service>"
```

If no spans appear:
1. Verify `-javaagent:` path is correct and the JAR is readable
2. Check `OTEL_EXPORTER_OTLP_ENDPOINT` and network connectivity to the collector
3. Add `-Dotel.javaagent.debug=true` to JVM flags to see agent startup logs
4. Confirm `OTEL_SERVICE_NAME` is set — without it, service appears as `unknown_service`

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

Expected: `OTEL_SERVICE_NAME=<service>` — not hardcoded in code.

**Step 4 — Check agent version**

```bash
# Check JAR manifest for Implementation-Version
kubectl exec -n <ns> <pod> -- sh -c 'unzip -p /path/to/opentelemetry-javaagent.jar META-INF/MANIFEST.MF | grep Implementation-Version'
# or: check the build pipeline / dependency declaration
mvn dependency:tree | grep opentelemetry-javaagent
# or: ./gradlew dependencies | grep opentelemetry-javaagent
```

Expected: `Implementation-Version: 2.26.0`. If older: update and redeploy.

**Step 5 — Check `-alpha` artifact versions match agent**

```bash
mvn dependency:tree | grep opentelemetry-instrumentation
# or: ./gradlew dependencies | grep opentelemetry-instrumentation
```

All `-alpha` artifacts must match agent version (e.g., `2.26.0-alpha` with agent v2.26.0).

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

Search for unclosed spans or scopes:

```bash
grep -rn "span\.end()" src/main/java/
# Verify each span.end() is inside a finally block, not only in try
grep -rn "makeCurrent()" src/main/java/
# Verify each makeCurrent() result is used with try-with-resources
```

**Step 11 — Check exporter configuration**

```bash
kubectl exec -n <ns> <pod> -- env | grep OTEL_EXPORTER
```

Expected:
- `OTEL_EXPORTER_OTLP_ENDPOINT` set (no `.setEndpoint()` hardcoded in code)
- No `OtlpGrpcSpanExporter` without autoconfigure module

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
- Agent: [version]
- BOM: [version]
- -alpha artifacts: [match/mismatch]
```

## Instrumentation Quality Rules

**A1 — Every service boundary has a span.** Each inbound HTTP/gRPC handler and each outbound call must produce a span. No gaps at service edges.

**A2 — Span names are low-cardinality.** No user IDs, request IDs, or raw URL paths in span names. Use `{verb} {template}` pattern.

**A3 — Error spans have descriptions.** Every span with `StatusCode.ERROR` must have a non-empty description string.

**A4 — Resource attributes are externally configurable.** `service.name`, `service.version`, and `deployment.environment.name` must be settable via env vars without a code change.

**A5 — No orphan spans.** Every span except root must have a parent. Scheduled jobs and queue consumers must create a root span, not inherit an unrelated parent.
