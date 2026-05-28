# Endpoint, Protocol, and Troubleshooting — Java

## OTLP Protocol Reference

| Protocol | Port | Path auto-appended by SDK? | Exporter class |
|---|---|---|---|
| OTLP/gRPC | 4317 | No | `OtlpGrpcSpanExporter` |
| OTLP/HTTP | 4318 | Yes (`/v1/traces`, `/v1/metrics`, `/v1/logs`) | `OtlpHttpSpanExporter` |

Protocol defaults differ by path — do not assume gRPC everywhere:

| Path | Default protocol | Default port | Notes |
|------|-----------------|--------------|-------|
| Java agent 2.x | `http/protobuf` | 4318 | Changed from gRPC in agent 2.0 |
| Programmatic `OtlpHttpSpanExporter` | `http/protobuf` | 4318 | HTTP exporters auto-append `/v1/traces` etc. |
| Autoconfigure module (`opentelemetry-sdk-extension-autoconfigure`) | `grpc` | 4317 | Reads `OTEL_EXPORTER_OTLP_PROTOCOL` |

HTTP exporters auto-append the signal path — do not include `/v1/traces` in `OTEL_EXPORTER_OTLP_ENDPOINT`.

## Tsuga Endpoint Configuration

**Programmatic (gRPC):**

```java
OtlpGrpcSpanExporter traceExporter = OtlpGrpcSpanExporter.builder()
    .setEndpoint("https://ingest.<region>.tsuga.cloud:443")
    .addHeader("tsuga-ingestion-key", System.getenv("TSUGA_INGESTION_KEY"))
    .build();
```

**Programmatic (HTTP):**

```java
OtlpHttpSpanExporter traceExporter = OtlpHttpSpanExporter.builder()
    .setEndpoint("https://ingest.<region>.tsuga.cloud:443/v1/traces")
    .addHeader("tsuga-ingestion-key", System.getenv("TSUGA_INGESTION_KEY"))
    .build();
```

**Via environment variables (recommended — works with both agent and manual SDK):**

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://ingest.<region>.tsuga.cloud:443
OTEL_EXPORTER_OTLP_HEADERS=tsuga-ingestion-key=<your-key>
OTEL_EXPORTER_OTLP_PROTOCOL=grpc  # or http/protobuf
```

**Java agent with Tsuga:**

```bash
java -javaagent:opentelemetry-javaagent.jar \
     -Dotel.service.name=my-service \
     -Dotel.exporter.otlp.endpoint=https://ingest.<region>.tsuga.cloud:443 \
     -Dotel.exporter.otlp.headers=tsuga-ingestion-key=<your-key> \
     -Dotel.exporter.otlp.protocol=grpc \
     -jar myapp.jar
```

## Common Issues

### No spans arriving

1. **Agent not on classpath:** Verify `-javaagent:` path exists and is readable by the JVM process.
2. **Wrong endpoint format:** For gRPC, use `https://host:443` (no path). For HTTP, the SDK appends `/v1/traces`.
3. **TLS mismatch:** Tsuga uses TLS on port 443. Do not use `WithInsecure()` equivalent — the Java gRPC exporter defaults to TLS for `https://` URIs.
4. **Missing service name:** Without `OTEL_SERVICE_NAME`, spans arrive as `unknown_service:java` — hard to find in Tsuga.
   > To determine the correct service name, see `references/resource-attributes.md` → **Resolve resource attribute values**.

### Debug mode for the Java agent

```bash
java -javaagent:opentelemetry-javaagent.jar \
     -Dotel.javaagent.debug=true \
     -jar myapp.jar 2>&1 | grep -i "otel\|opentelemetry"
```

This prints library detection, instrumentation activation, and export attempts to stderr.

### `ClassNotFoundException` or `NoClassDefFoundError`

Usually caused by version mismatch between the agent and instrumentation library artifacts. Check:

```bash
mvn dependency:tree | grep opentelemetry-instrumentation
```

All `-alpha` packages must match the agent version exactly (e.g., 2.26.0-alpha with agent v2.26.0).

### Spans arrive but metrics do not

Metrics require `SdkMeterProvider` with a `PeriodicMetricReader`. Common mistake: forgetting to call `registerMetricReader` or not setting `SdkMeterProvider` as the global provider.

With the agent, enable the metrics exporter:

```bash
-Dotel.metrics.exporter=otlp
```

### gRPC UNAVAILABLE / connection refused

- Port 4317 blocked by firewall or security group
- Using HTTP endpoint URL (`https://`) with gRPC exporter — gRPC expects `host:port` format resolved via DNS, not a URL with scheme
- In Kubernetes: the sidecar collector is not running or has a different service name

### Thread pool context loss

Executors created before OTel SDK init may not propagate context. Use context-aware wrappers:

```java
import io.opentelemetry.context.Context;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

ExecutorService executor = Context.taskWrapping(Executors.newFixedThreadPool(10));
// Now all tasks submitted preserve the calling thread's OTel context
```

## Shutdown / Flush

The Java SDK buffers spans in `BatchSpanProcessor`. On JVM shutdown, the shutdown hook must complete before the process exits.

**Recommended shutdown hook:**

```java
OpenTelemetrySdk openTelemetry = OpenTelemetrySdk.builder()
    .setTracerProvider(tracerProvider)
    .setMeterProvider(meterProvider)
    .buildAndRegisterGlobal();

// Registers shutdown hook that calls openTelemetry.close()
Runtime.getRuntime().addShutdownHook(new Thread(openTelemetry::close));
```

`openTelemetry.close()` calls `SdkTracerProvider.close()` and `SdkMeterProvider.close()`, which flush in-flight data and shut down exporters.

**Spring Boot — use `@PreDestroy`:**

```java
@Configuration
public class OtelConfig {
    private OpenTelemetrySdk sdk;

    @Bean
    public OpenTelemetry openTelemetry() {
        sdk = OpenTelemetrySdk.builder()
            .setTracerProvider(/* ... */)
            .buildAndRegisterGlobal();
        return sdk;
    }

    @PreDestroy
    public void shutdown() {
        if (sdk != null) sdk.close();
    }
}
```

**Common shutdown mistakes:**

- Relying on GC to close providers — `BatchSpanProcessor` does not flush on GC
- Calling `System.exit()` before the shutdown hook runs
- Shutdown timeout too short — default is 5 seconds; increase for high-volume services:

```java
BatchSpanProcessor.builder(exporter)
    .setExporterTimeout(Duration.ofSeconds(10))
    .setScheduleDelay(Duration.ofSeconds(5))
    .build();
```

## Resilience: Collector Unavailable

When the OTLP collector is unreachable, the Java OTel SDK does **not** throw exceptions to application code. The `BatchSpanProcessor` retries exports with backoff; when the buffer fills, oldest spans are dropped. The service continues normally.

**Default exporter behavior:** `OtlpHttpSpanExporter` retries on failure with configurable retry policy. Errors are logged via `java.util.logging`, not thrown.

**Conditional setup:**

```java
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;
import io.opentelemetry.exporter.otlp.http.trace.OtlpHttpSpanExporter;

// OtlpHttpSpanExporter.builder().build() reads OTEL_EXPORTER_OTLP_ENDPOINT automatically
// (default: http://localhost:4318). Consistent with HTTP/protobuf default.
SdkTracerProvider.Builder builder = SdkTracerProvider.builder().setResource(resource);
String endpoint = System.getenv("OTEL_EXPORTER_OTLP_ENDPOINT");

if (endpoint != null && !endpoint.isEmpty()) {
    OtlpHttpSpanExporter exporter = OtlpHttpSpanExporter.builder()
        .setTimeout(Duration.ofSeconds(10))
        .build();   // reads OTEL_EXPORTER_OTLP_ENDPOINT — do not call .setEndpoint()
    builder.addSpanProcessor(BatchSpanProcessor.builder(exporter).build());
}
// If no endpoint: no exporter added — SDK is functional, no export attempted
SdkTracerProvider tracerProvider = builder.build();
```

**Java agent:** The javaagent handles collector unavailability automatically — the service starts and runs even if the collector is down.

**Disable OTel:**
```bash
OTEL_SDK_DISABLED=true java -jar app.jar
# or with javaagent:
OTEL_JAVAAGENT_ENABLED=false java -javaagent:opentelemetry-javaagent.jar -jar app.jar
```
