# Local Verification — Java

## Overview

Before routing telemetry to a production collector, verify Java instrumentation by printing spans to stdout using `LoggingSpanExporter`. The Java agent supports `OTEL_TRACES_EXPORTER=logging` natively, making it easy to enable console output without code changes. For short-lived applications and tests, explicit SDK shutdown is required to avoid dropped spans.

## LoggingSpanExporter

`LoggingSpanExporter` writes each finished span to `java.util.logging` at `INFO` level. It is included in the `opentelemetry-exporter-logging` artifact.

**Maven dependency:**

```xml
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-exporter-logging</artifactId>
</dependency>
```

**SDK configuration:**

```java
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.exporter.logging.LoggingSpanExporter;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.resources.Resource;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.SimpleSpanProcessor;
import io.opentelemetry.semconv.ServiceAttributes;

// NOTE: ResourceAttributes was removed in semconv-java 1.24.0.
// Use namespace-specific classes: ServiceAttributes for service.name/version,
// DeploymentIncubatingAttributes (from opentelemetry-semconv-incubating) for deployment.environment.name.
Resource resource = Resource.getDefault()
    .merge(Resource.create(Attributes.of(ServiceAttributes.SERVICE_NAME, "my-service")));

SdkTracerProvider tracerProvider = SdkTracerProvider.builder()
    .addSpanProcessor(SimpleSpanProcessor.create(LoggingSpanExporter.create()))
    .setResource(resource)
    .build();

OpenTelemetrySdk openTelemetry = OpenTelemetrySdk.builder()
    .setTracerProvider(tracerProvider)
    .build();

Tracer tracer = openTelemetry.getTracer("my-service");
```

Each span appears in log output as a single line including trace ID, span ID, parent span ID, name, duration, and attributes.

⚠️ Output is formatted text (not JSON). For JSON output, see `OtlpJsonLoggingSpanExporter` below.

## OtlpJsonLoggingSpanExporter (OTLP JSON output)

`OtlpJsonLoggingSpanExporter` writes each finished span as a `{"resourceSpans":[...]}` OTLP JSON object to `java.util.logging`. Use this when you need parseable JSON output.

**Maven dependency:**

```xml
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-exporter-logging-otlp</artifactId>
</dependency>
```

**SDK configuration** (drop-in swap for `LoggingSpanExporter`):

```java
import io.opentelemetry.exporter.logging.otlp.OtlpJsonLoggingSpanExporter;

SdkTracerProvider tracerProvider = SdkTracerProvider.builder()
    .addSpanProcessor(SimpleSpanProcessor.create(OtlpJsonLoggingSpanExporter.create()))
    .setResource(resource)
    .build();
```

**Output format:** One `{"resourceSpans":[...]}` JSON object per JUL log line, **camelCase keys** per the
[OTLP spec](https://opentelemetry.io/docs/specs/otlp/#json-protobuf-encoding). Example:

```
INFO io.opentelemetry.exporter.logging.otlp.OtlpJsonLoggingSpanExporter - {"resourceSpans":[{"resource":{...},"scopeSpans":[{"spans":[{"traceId":"...","spanId":"...","name":"http.request",...}]}]}]}
```

Use `OtlpJsonLoggingSpanExporter` when you need parseable OTLP JSON. Use `LoggingSpanExporter` when you want human-readable text output.

## SimpleSpanProcessor vs BatchSpanProcessor

| | `SimpleSpanProcessor` | `BatchSpanProcessor` |
|---|---|---|
| Export timing | Synchronous, on span end | Async, background thread |
| Local testing | Preferred — spans appear immediately | Requires `shutdown()` to flush; may miss spans |
| Production | Not recommended — adds latency per span | Correct choice |

For unit tests and local scripts, always use `SimpleSpanProcessor`. For integration tests that exercise the full pipeline, use `BatchSpanProcessor` and call `shutdown()` in a `@AfterEach` or `finally` block.

## Short-Lived Applications

Applications that exit after completing a task must call `shutdown()` or the batch processor's background thread will not have flushed its buffer.

```java
SdkTracerProvider tracerProvider = SdkTracerProvider.builder()
    .addSpanProcessor(SimpleSpanProcessor.create(LoggingSpanExporter.create()))
    .build();

// Register JVM shutdown hook
Runtime.getRuntime().addShutdownHook(new Thread(tracerProvider::shutdown));

Tracer tracer = openTelemetry.getTracer("my-job");
Span span = tracer.spanBuilder("batch.process").startSpan();

try (Scope scope = span.makeCurrent()) {
    processRecords();
} finally {
    span.end();
    // Explicit shutdown for scripts (shutdown hook is a fallback)
    tracerProvider.shutdown().join(10, TimeUnit.SECONDS);
}
```

When using `BatchSpanProcessor`, replace `join(10, TimeUnit.SECONDS)` with the same timeout to give the exporter time to flush. For `SimpleSpanProcessor`, the call completes immediately.

## OTEL_TRACES_EXPORTER=logging Environment Variable (Java Agent)

The Java agent natively supports the `OTEL_TRACES_EXPORTER=logging` environment variable. No code changes are required.

```bash
OTEL_TRACES_EXPORTER=logging \
OTEL_SERVICE_NAME=my-service \
java -javaagent:opentelemetry-javaagent.jar -jar app.jar
```

Equivalently as a JVM system property:

```bash
java \
  -javaagent:opentelemetry-javaagent.jar \
  -Dotel.traces.exporter=logging \
  -Dotel.service.name=my-service \
  -jar app.jar
```

This applies only when running with the Java agent. For programmatic SDK setup, configure `LoggingSpanExporter` explicitly as shown above.

## Local Collector with Debug Exporter

Run `otelcol-contrib` locally to validate the full OTLP export path. The `debug` exporter prints every received span and metric with full attribute detail.

```yaml
# otelcol-config.yaml — local debug collector
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

exporters:
  debug:
    verbosity: detailed

service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [debug]
    metrics:
      receivers: [otlp]
      exporters: [debug]
```

Point the Java agent at the local collector:

```bash
# Agent 2.x defaults to http/protobuf on port 4318 — the collector YAML above accepts both
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 \
OTEL_SERVICE_NAME=my-service \
java -javaagent:opentelemetry-javaagent.jar -jar app.jar
# For gRPC: change endpoint to http://localhost:4317 and add OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```
