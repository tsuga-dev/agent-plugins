# Auto-Instrumentation — Java

## Overview

The OpenTelemetry Java Agent (`opentelemetry-javaagent.jar`) provides zero-code auto-instrumentation for Java applications. It uses bytecode instrumentation (via a Java agent) to patch supported libraries at JVM load time. No code changes are required.

## Installation

```bash
curl -L https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.26.0/opentelemetry-javaagent.jar \
  -o opentelemetry-javaagent.jar
```

Or download the latest release:

```bash
curl -L https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar \
  -o opentelemetry-javaagent.jar
```

## Running with the Agent

```bash
java -javaagent:/path/to/opentelemetry-javaagent.jar \
     -Dotel.service.name=my-service \
     -Dotel.exporter.otlp.endpoint=http://localhost:4318 \
     -Dotel.resource.attributes=deployment.environment.name=production \
     -jar myapp.jar
# Agent 2.x default: http/protobuf on port 4318. For gRPC on port 4317:
# add -Dotel.exporter.otlp.protocol=grpc and change endpoint to http://localhost:4317
```

Via environment variables:

```bash
export OTEL_SERVICE_NAME=my-service
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
export OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production
java -javaagent:/path/to/opentelemetry-javaagent.jar -jar myapp.jar
```

## What Gets Covered Automatically

The Java agent v2.26.0 instruments 100+ libraries. Key categories:

| Category | Examples |
|---|---|
| HTTP servers | Spring MVC, Spring WebFlux, Servlet, Jersey, Dropwizard, Micronaut |
| HTTP clients | Apache HttpClient, OkHttp, HttpURLConnection, Vert.x WebClient |
| gRPC | `io.grpc:grpc-core` (both server and client interceptors) |
| JDBC | All JDBC-compliant drivers (PostgreSQL, MySQL, Oracle, H2, etc.) |
| JPA / Hibernate | Hibernate ORM — SQL query spans |
| Messaging | Kafka, RabbitMQ, JMS, ActiveMQ, AWS SQS |
| Caching | Redis (Jedis, Lettuce), Memcached |
| Scheduling | Spring Scheduled, Quartz |
| AWS SDK | AWS SDK v1 and v2 |
| Logging | Logback MDC, Log4j2 ThreadContext (trace context auto-injected) |

## Configuring Agent Behavior

Suppress specific instrumentations:

```bash
# Disable JDBC instrumentation
-Dotel.instrumentation.jdbc.enabled=false

# Disable specific HTTP client
-Dotel.instrumentation.apache-httpclient.enabled=false
```

Capture SQL query text (disabled by default for privacy):

```bash
-Dotel.instrumentation.jdbc.statement-sanitizer.enabled=false
```

Capture HTTP request/response headers:

```bash
-Dotel.instrumentation.http.server.capture-request-headers=X-Correlation-Id,X-User-Id
-Dotel.instrumentation.http.server.capture-response-headers=X-Request-Id
```

## Agent + Manual Instrumentation

You can use the Java agent together with manual `@WithSpan` annotations from the `opentelemetry-instrumentation-annotations` package:

```xml
<dependency>
    <groupId>io.opentelemetry.instrumentation</groupId>
    <artifactId>opentelemetry-instrumentation-annotations</artifactId>
    <version>2.26.0</version>
</dependency>
```

> `opentelemetry-instrumentation-annotations` is a **stable** artifact — use `2.26.0`, not `2.26.0-alpha`. Only library instrumentation artifacts (e.g., `opentelemetry-logback-mdc-1.0`) carry the `-alpha` suffix.

```java
import io.opentelemetry.instrumentation.annotations.WithSpan;
import io.opentelemetry.instrumentation.annotations.SpanAttribute;

@WithSpan("user.findById")
public User findById(@SpanAttribute("user.id") long userId) {
    return userRepository.findById(userId);
}
```

When the agent is present, `@WithSpan` creates an OTel span automatically. Without the agent, the annotation is a no-op.

## Extension Mechanism (Custom Instrumentations)

For proprietary libraries not covered by the agent, write an agent extension:

```java
// Custom InstrumentationModule
@AutoService(InstrumentationModule.class)
public class MyLibraryInstrumentationModule extends InstrumentationModule {
    public MyLibraryInstrumentationModule() {
        super("my-library", "my-library-1.0");
    }
    // ...
}
```

Build as a JAR and load with:

```bash
java -javaagent:opentelemetry-javaagent.jar \
     -Dotel.javaagent.extensions=my-extension.jar \
     -jar myapp.jar
```

## What Needs Manual Instrumentation

Even with the agent, you need manual spans for:

- Business logic not tied to a library call (e.g., `order.validate`, `pricing.calculate`)
- Custom protocol handlers
- Batch processing loops where you want per-item spans
- Context propagation across thread pools not managed by a supported framework

## Spring Boot Starter

For Spring Boot projects, the `opentelemetry-spring-boot-starter` provides programmatic SDK configuration as a Spring auto-configuration:

```xml
<dependency>
    <groupId>io.opentelemetry.instrumentation</groupId>
    <artifactId>opentelemetry-spring-boot-starter</artifactId>
    <version>2.26.0</version>
</dependency>
```

> `opentelemetry-spring-boot-starter` is a **stable** artifact — use `2.26.0`, not `2.26.0-alpha`.

Configure in `application.yml`:

```yaml
otel:
  service:
    name: my-service
  exporter:
    otlp:
      endpoint: http://localhost:4318  # http/protobuf default; use 4317 for gRPC
  traces:
    sampler: parentbased_always_on
```

This is an alternative to the `-javaagent` approach, suitable for programmatic control.

## Quarkus

Quarkus has a native OTel extension — do not use the Java agent with Quarkus.

**Dependency:**
```xml
<dependency>
  <groupId>io.quarkus</groupId>
  <artifactId>quarkus-opentelemetry</artifactId>
</dependency>
```

**Configuration (`application.properties`):**
```properties
# Quarkus defaults to gRPC protocol (port 4317). For http/protobuf, use port 4318 and set protocol.
quarkus.otel.exporter.otlp.traces.endpoint=http://localhost:4317
quarkus.otel.traces.sampler=parentbased_always_on
# Service name is picked up from quarkus.application.name
quarkus.application.name=my-service
```

**What's auto-instrumented:** HTTP endpoints (REST), reactive routes, CDI beans annotated with `@WithSpan`, outbound REST client calls.

**Custom spans:** Use `@WithSpan` (from `io.opentelemetry.instrumentation.annotations`) or inject `Tracer` via CDI:
```java
@Inject
Tracer tracer;
```

**Native image:** Quarkus OTel extension is fully compatible with GraalVM native compilation. The Java agent is not.
