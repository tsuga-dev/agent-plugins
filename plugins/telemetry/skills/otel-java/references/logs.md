# Logs — Java OTel

> **Last verified:** 2026-03-23 | SDK: `opentelemetry-bom` 1.60.1 | Agent: `opentelemetry-javaagent` 2.26.0
>
> Logs SDK is **stable** as of SDK 1.60.1.

## Path Selection

| Scenario | Path |
|----------|------|
| Running the Java agent | **Path A** — zero-code MDC auto-injection |
| Logback + want OTel log pipeline | **Path B** — Logback OTel appender |
| Log4j2 + want OTel log pipeline | **Path C** — Log4j2 OTel appender |
| No agent, no appender, minimal setup | **Path D** — manual MDC injection |

## Path A — Java Agent (Recommended, Zero-Code)

With the Java agent, `trace_id`, `span_id`, and `trace_flags` are **automatically injected** into:
- SLF4J/Logback MDC
- Log4j2 ThreadContext

No code changes are needed. Only configure your logging framework to output the MDC fields.

**Logback pattern (include MDC fields):**

```xml
<!-- logback.xml -->
<appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
  <encoder>
    <pattern>%d{ISO8601} %-5level [%X{trace_id},%X{span_id}] %logger{36} - %msg%n</pattern>
  </encoder>
</appender>
```

**Log4j2 pattern:**

```xml
<!-- log4j2.xml -->
<Console name="CONSOLE" target="SYSTEM_OUT">
  <PatternLayout pattern="%d{ISO8601} %-5p [%X{trace_id},%X{span_id}] %c{1} - %msg%n"/>
</Console>
```

## Path B — Logback OTel Appender (Programmatic)

Bridges Logback log records into the OTel log pipeline AND injects `trace_id`/`span_id`.

**Dependency (`-alpha` version must match agent version):**

```xml
<dependency>
    <groupId>io.opentelemetry.instrumentation</groupId>
    <artifactId>opentelemetry-logback-appender-1.0</artifactId>
    <version>2.26.0-alpha</version>
</dependency>
```

**logback.xml:**

```xml
<appender name="OpenTelemetry"
          class="io.opentelemetry.instrumentation.logback.appender.v1_0.OpenTelemetryAppender">
</appender>

<root level="INFO">
    <appender-ref ref="OpenTelemetry"/>
</root>
```

This appender:
1. Forwards all log records to the OTel log pipeline (visible in Tsuga as log telemetry)
2. Auto-injects `trace_id`, `span_id`, `trace_flags` from the current span context

## Path C — Log4j2 OTel Appender (Programmatic)

```xml
<dependency>
    <groupId>io.opentelemetry.instrumentation</groupId>
    <artifactId>opentelemetry-log4j-appender-2.17</artifactId>
    <version>2.26.0-alpha</version>
</dependency>
```

**log4j2.xml:**

```xml
<Appenders>
  <OpenTelemetry name="OpenTelemetry"/>
</Appenders>

<Loggers>
  <Root level="info">
    <AppenderRef ref="OpenTelemetry"/>
  </Root>
</Loggers>
```

## Path D — Manual MDC Injection (Without Agent or Appender)

Use when you cannot use the agent or appender but need trace correlation in logs.

```java
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanContext;
import org.slf4j.MDC;

SpanContext sc = Span.current().getSpanContext();
if (sc.isValid()) {
    MDC.put("trace_id", sc.getTraceId());
    MDC.put("span_id", sc.getSpanId());
    MDC.put("trace_flags", sc.getTraceFlags().asHex());
}
try {
    // ... log statements here ...
    log.info("Processing order {}", orderId);
} finally {
    // MUST clean up MDC to avoid context leaking across thread pool tasks
    MDC.remove("trace_id");
    MDC.remove("span_id");
    MDC.remove("trace_flags");
}
```

> **Thread pool warning:** If using a thread pool, MDC values persist on reused threads unless
> explicitly removed. Always clean up in `finally`.

## Verification

```bash
# Confirm logs arrive with trace correlation
tsuga logs search --query "context.service.name:<your-service> trace_id:*" --max-results 3

# If trace_id is present but spans are not linking
tsuga spans search --query "context.service.name:<your-service> traceId:<trace-id-from-log>"
```

If verification fails:
- `trace_id` absent from logs → `tsuga-debug-missing-trace-propagation`
- Zero log results → `tsuga-debug-no-data`
