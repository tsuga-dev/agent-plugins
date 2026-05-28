# Quick Start — Java OTel

> **Last verified:** 2026-03-23 | SDK: `opentelemetry-bom` 1.60.1 | Agent: `opentelemetry-javaagent` 2.26.0

> Run `java -version` — Java 8+ required (all current SDK versions). If below 8, stop and report to the user.

## Maven Setup (Recommended — BOM)

```xml
<dependencyManagement>
  <dependencies>
    <dependency>
      <groupId>io.opentelemetry</groupId>
      <artifactId>opentelemetry-bom</artifactId>
      <version>1.60.1</version>
      <type>pom</type>
      <scope>import</scope>
    </dependency>
  </dependencies>
</dependencyManagement>

<dependencies>
  <dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-api</artifactId>
  </dependency>
  <dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-sdk</artifactId>
  </dependency>
  <dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-exporter-otlp</artifactId>
  </dependency>
</dependencies>
```

**Log appender (match agent version — use `-alpha` suffix):**

```xml
<!-- Logback -->
<dependency>
    <groupId>io.opentelemetry.instrumentation</groupId>
    <artifactId>opentelemetry-logback-appender-1.0</artifactId>
    <version>2.26.0-alpha</version>
</dependency>

<!-- OR Log4j2 -->
<dependency>
    <groupId>io.opentelemetry.instrumentation</groupId>
    <artifactId>opentelemetry-log4j-appender-2.17</artifactId>
    <version>2.26.0-alpha</version>
</dependency>
```

## Gradle Setup

```groovy
implementation platform('io.opentelemetry:opentelemetry-bom:1.60.1')
implementation 'io.opentelemetry:opentelemetry-api'
implementation 'io.opentelemetry:opentelemetry-sdk'
implementation 'io.opentelemetry:opentelemetry-exporter-otlp'

// Log appender (match agent version):
implementation 'io.opentelemetry.instrumentation:opentelemetry-logback-appender-1.0:2.26.0-alpha'
```

## Programmatic SDK Initialization

```java
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.exporter.otlp.http.logs.OtlpHttpLogRecordExporter;
import io.opentelemetry.exporter.otlp.http.metrics.OtlpHttpMetricExporter;
import io.opentelemetry.exporter.otlp.http.trace.OtlpHttpSpanExporter;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.logs.SdkLoggerProvider;
import io.opentelemetry.sdk.logs.export.BatchLogRecordProcessor;
import io.opentelemetry.sdk.metrics.SdkMeterProvider;
import io.opentelemetry.sdk.metrics.export.PeriodicMetricReader;
import io.opentelemetry.sdk.resources.Resource;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;

// Resource.getDefault() reads OTEL_SERVICE_NAME and OTEL_RESOURCE_ATTRIBUTES automatically.
// To add service.version in code:
//   Resource.getDefault().merge(Resource.builder()
//       .put(ServiceAttributes.SERVICE_VERSION, "1.0.0").build())
// NOTE: Use ServiceAttributes (from opentelemetry-semconv), not the removed ResourceAttributes.
Resource resource = Resource.getDefault();

SdkTracerProvider tracerProvider = SdkTracerProvider.builder()
    .setResource(resource)
    .addSpanProcessor(BatchSpanProcessor.builder(
        // .build() with no .setEndpoint() reads OTEL_EXPORTER_OTLP_ENDPOINT
        // Default: http://localhost:4318/v1/traces (HTTP/protobuf)
        OtlpHttpSpanExporter.builder().build()
    ).build())
    .build();

SdkMeterProvider meterProvider = SdkMeterProvider.builder()
    .setResource(resource)
    .registerMetricReader(PeriodicMetricReader.builder(
        OtlpHttpMetricExporter.builder().build()
    ).build())
    .build();

// Logs SDK is stable as of SDK 1.60.1
SdkLoggerProvider loggerProvider = SdkLoggerProvider.builder()
    .setResource(resource)
    .addLogRecordProcessor(BatchLogRecordProcessor.builder(
        OtlpHttpLogRecordExporter.builder().build()
    ).build())
    .build();

OpenTelemetrySdk openTelemetry = OpenTelemetrySdk.builder()
    .setTracerProvider(tracerProvider)
    .setMeterProvider(meterProvider)
    .setLoggerProvider(loggerProvider)
    .buildAndRegisterGlobal();

// Always register a shutdown hook — BatchSpanProcessor will not flush on GC
Runtime.getRuntime().addShutdownHook(new Thread(openTelemetry::close));
```

**Critical scope management rule:**

```java
// CORRECT — Scope with try-with-resources; span.end() always in finally
Span span = tracer.spanBuilder("op.name").startSpan();
try (Scope scope = span.makeCurrent()) {   // Scope closes automatically
    doWork();
} catch (Exception e) {
    span.recordException(e);
    span.setStatus(StatusCode.ERROR, "op failed");
    throw e;
} finally {
    span.end();   // MUST be in finally — not in try block
}

// WRONG — span.end() skipped when doWork() throws
Span span = tracer.spanBuilder("op.name").startSpan();
try (Scope scope = span.makeCurrent()) {
    doWork();
    span.end();  // not reached if doWork() throws — span is never closed
} catch (Exception e) {
    throw e;
}
// span.end() also missing from catch and any finally — span leaks
```

> **Note:** `span.makeCurrent()` returns a `Scope`. Closing `Scope` does NOT end the span.
> Both must be closed. `Scope` → try-with-resources; `Span` → `finally` block.

## Environment Variables

```bash
# Minimum required — see references/resource-attributes.md to resolve the correct service name
OTEL_SERVICE_NAME=my-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318   # HTTP/protobuf default

# Recommended
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production,service.version=1.4.2

# Set per-signal protocols explicitly (defaults are SDK-dependent)
OTEL_EXPORTER_OTLP_TRACES_PROTOCOL=http/protobuf
OTEL_EXPORTER_OTLP_METRICS_PROTOCOL=http/protobuf
OTEL_EXPORTER_OTLP_LOGS_PROTOCOL=http/protobuf

# gRPC opt-in (Collector gRPC receiver on port 4317)
# OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
# OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```

## Java Agent (Zero-Code Auto-Instrumentation)

```bash
# Download agent v2.26.0
curl -L https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.26.0/opentelemetry-javaagent.jar \
  -o opentelemetry-javaagent.jar

# Run — agent reads all OTEL_* env vars automatically
# Agent 2.x defaults to HTTP/protobuf on port 4318
OTEL_SERVICE_NAME=my-service \
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 \
java -javaagent:opentelemetry-javaagent.jar -jar myapp.jar
```

The agent instruments 100+ libraries automatically (Spring, gRPC, JDBC, Kafka, etc.) with zero code changes. See `references/auto-instrumentation.md` for full coverage list.

## Post-Deploy Verification

```bash
# Confirm traces arrive
tsuga spans search --query "context.service.name:my-service" --max-results 5

# Confirm logs with trace correlation
tsuga logs search --query "context.service.name:my-service trace_id:*" --max-results 3

# Confirm metrics
tsuga metrics list --filter "service.name=my-service"
```

If no data: `tsuga-debug-no-data` skill.
If traces don't link across services: `tsuga-debug-missing-trace-propagation` skill.
