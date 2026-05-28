# Distributed Context Propagation — Java

## Overview

Trace context must be explicitly propagated across service boundaries. The W3C TraceContext headers (`traceparent`, `tracestate`) carry the trace ID and span ID between services. With the Java agent, HTTP propagation is automatic. For manual SDK setups, you configure a `TextMapPropagator`.

## Inbound: Server Context Extraction

**With the Java agent:** Fully automatic for all supported frameworks (Servlet, Spring MVC, Spring WebFlux, gRPC server, etc.). The agent reads `traceparent` and sets the parent span context before your handler runs.

**Manual extraction (custom transport):**

```java
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.propagation.TextMapGetter;

// Define a getter for your carrier type
TextMapGetter<Map<String, String>> getter = new TextMapGetter<>() {
    @Override
    public Iterable<String> keys(Map<String, String> carrier) {
        return carrier.keySet();
    }

    @Override
    public String get(Map<String, String> carrier, String key) {
        return carrier.get(key.toLowerCase());
    }
};

// Extract parent context from incoming headers
Context parentContext = GlobalOpenTelemetry.getPropagators()
    .getTextMapPropagator()
    .extract(Context.current(), incomingHeaders, getter);

// Start span as child of the extracted context
Tracer tracer = GlobalOpenTelemetry.getTracer("my-service");
Span span = tracer.spanBuilder("handle.request")
    .setParent(parentContext)
    .startSpan();
try (Scope scope = span.makeCurrent()) {
    doWork();
} finally {
    span.end();
}
```

**Servlet filter (manual):**

```java
@WebFilter("/*")
public class TracingFilter implements Filter {
    @Override
    public void doFilter(ServletRequest req, ServletResponse res, FilterChain chain)
            throws IOException, ServletException {

        HttpServletRequest httpReq = (HttpServletRequest) req;

        TextMapGetter<HttpServletRequest> getter = new TextMapGetter<>() {
            @Override
            public Iterable<String> keys(HttpServletRequest carrier) {
                return Collections.list(carrier.getHeaderNames());
            }
            @Override
            public String get(HttpServletRequest carrier, String key) {
                return carrier.getHeader(key);
            }
        };

        Context parentCtx = GlobalOpenTelemetry.getPropagators()
            .getTextMapPropagator()
            .extract(Context.current(), httpReq, getter);

        Span span = GlobalOpenTelemetry.getTracer("my-service")
            .spanBuilder("http.server")
            .setParent(parentCtx)
            .startSpan();
        try (Scope scope = span.makeCurrent()) {
            chain.doFilter(req, res);
        } finally {
            span.end();
        }
    }
}
```

## Outbound: Client Context Injection

**With the Java agent:** Automatic for all supported HTTP clients (Apache HttpClient, OkHttp, HttpURLConnection, etc.).

**Manual injection with Apache HttpClient:**

```java
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.propagation.TextMapSetter;
import org.apache.http.client.methods.HttpGet;

TextMapSetter<HttpGet> setter = (carrier, key, value) -> carrier.setHeader(key, value);

HttpGet request = new HttpGet("https://downstream-service/api");
GlobalOpenTelemetry.getPropagators()
    .getTextMapPropagator()
    .inject(Context.current(), request, setter);

// Execute request with injected headers
CloseableHttpResponse response = httpClient.execute(request);
```

**Manual injection with OkHttp:**

```java
TextMapSetter<okhttp3.Request.Builder> setter =
    (carrier, key, value) -> carrier.header(key, value);

okhttp3.Request.Builder builder = new okhttp3.Request.Builder().url(url);
GlobalOpenTelemetry.getPropagators()
    .getTextMapPropagator()
    .inject(Context.current(), builder, setter);

okhttp3.Request request = builder.build();
```

## Message Queue Propagation

> **→ See `references/async-messaging.md`** for Kafka, JMS/ActiveMQ, AWS SQS, and RabbitMQ patterns
> with span Links, semconv attributes, and auto-instrumentation coverage table.

## Anti-Pattern: Do Not Merge Separate Workflows

Creating a child span that parents an unrelated workflow creates misleading traces. Each independent background job or queue consumer should start a new root span and **link** to the producer trace rather than making it a parent.

```java
// WRONG — makes consumer appear as child of producer HTTP request
Span span = tracer.spanBuilder("process.job")
    .setParent(extractedProducerContext)
    .startSpan();

// CORRECT — new root, linked to producer for cross-trace navigation
Span span = tracer.spanBuilder("process.job")
    .setNoParent()
    .addLink(Span.fromContext(extractedProducerContext).getSpanContext())
    .startSpan();
```

## Configuring Propagators

The Java agent defaults to W3C TraceContext + W3C Baggage. To add B3 support:

Use the default W3C TraceContext + Baggage propagators for all new services. Add `b3multi` only when interoperating with Zipkin-instrumented services, legacy Spring Cloud Sleuth (pre-3.x), or an Istio/Envoy mesh configured for B3. To confirm whether B3 is in use, look for `X-B3-TraceId` headers in captured traffic.

```bash
-Dotel.propagators=tracecontext,baggage,b3multi
```

For programmatic SDK:

```java
OpenTelemetrySdk.builder()
    .setPropagators(ContextPropagators.create(
        TextMapPropagator.composite(
            W3CTraceContextPropagator.getInstance(),
            W3CBaggagePropagator.getInstance()
        )
    ))
    .buildAndRegisterGlobal();
```

## Tsuga Trace Continuity Validation

After instrumenting propagation, verify parent/child linkage:

```bash
tsuga spans search --query "context.service.name:<caller-service>" --max-results 5
# Note traceId values from results
tsuga spans search --query "context.service.name:<callee-service> traceId:<trace-id>"
# parentSpanId on callee spans must match spanId from caller spans
```
