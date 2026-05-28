# Framework-Specific Recipes — Java

## Spring Boot

The Java agent auto-instruments Spring Boot out of the box — HTTP, JDBC, Kafka, and more. For additional manual spans, use `@WithSpan` or the programmatic API.

**Spring Boot Actuator health endpoint exclusion:**

```bash
# Exclude health check from tracing via agent config
-Dotel.instrumentation.spring-web.enabled=true
-Dotel.instrumentation.spring-webmvc.enabled=true
```

**Manual span in a Spring Service:**

```java
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Scope;
import org.springframework.stereotype.Service;

@Service
public class OrderService {

    private final Tracer tracer = GlobalOpenTelemetry.getTracer("com.myapp.orders");

    public Order processOrder(OrderRequest request) {
        Span span = tracer.spanBuilder("order.process")
            .setAttribute("order.id", request.getOrderId())
            .setAttribute("order.total_items", request.getItems().size())
            .startSpan();
        try (Scope scope = span.makeCurrent()) {
            validateOrder(request);
            Order order = persistOrder(request);
            return order;
        } catch (Exception e) {
            span.recordException(e);
            span.setStatus(StatusCode.ERROR, "order processing failed");
            throw e;
        } finally {
            span.end();
        }
    }
}
```

**`@WithSpan` annotation (requires `opentelemetry-instrumentation-annotations`):**

```java
import io.opentelemetry.instrumentation.annotations.WithSpan;
import io.opentelemetry.instrumentation.annotations.SpanAttribute;

@Service
public class InventoryService {

    @WithSpan("inventory.check")
    public boolean isAvailable(
            @SpanAttribute("product.id") String productId,
            @SpanAttribute("quantity") int quantity) {
        return inventoryRepository.check(productId, quantity);
    }
}
```

**Spring WebFlux (reactive):**

The Java agent handles reactive context propagation automatically. For manual spans in WebFlux:

```java
import io.opentelemetry.context.Context;
import io.opentelemetry.context.ContextKey;
import reactor.core.publisher.Mono;

@GetMapping("/reactive/{id}")
public Mono<Response> getReactive(@PathVariable String id) {
    Span span = tracer.spanBuilder("reactive.handler")
        .setAttribute("id", id)
        .startSpan();

    return Mono.fromCallable(() -> fetchData(id))
        .doOnSuccess(r -> span.end())
        .doOnError(e -> {
            span.recordException(e);
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.end();
        })
        .contextWrite(ctx -> ctx.put(Context.class, Context.current().with(span)));
}
```

## gRPC

The Java agent auto-instruments `io.grpc:grpc-core` for both server and client. For manual spans in gRPC handlers:

**Server interceptor (manual):**

```java
import io.grpc.Context;
import io.grpc.Contexts;
import io.grpc.Metadata;
import io.grpc.ServerCall;
import io.grpc.ServerCallHandler;
import io.grpc.ServerInterceptor;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.Tracer;

public class ServerTracingInterceptor implements ServerInterceptor {
    private final Tracer tracer;

    @Override
    public <Req, Resp> ServerCall.Listener<Req> interceptCall(
            ServerCall<Req, Resp> call, Metadata headers, ServerCallHandler<Req, Resp> next) {

        // When using the agent, span is already set; just add attributes
        Span span = Span.current();
        span.setAttribute("rpc.service", call.getMethodDescriptor().getServiceName());
        return next.startCall(call, headers);
    }
}
```

**gRPC client stub with propagation (manual, without agent):**

```java
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.propagation.TextMapSetter;
import io.grpc.ManagedChannel;
import io.grpc.Metadata;
import io.grpc.stub.MetadataUtils;

Metadata metadata = new Metadata();
GlobalOpenTelemetry.getPropagators().getTextMapPropagator()
    .inject(Context.current(), metadata,
        (carrier, key, value) ->
            carrier.put(Metadata.Key.of(key, Metadata.ASCII_STRING_MARSHALLER), value));

MyServiceGrpc.MyServiceBlockingStub stub = MyServiceGrpc.newBlockingStub(channel)
    .withInterceptors(MetadataUtils.newAttachHeadersInterceptor(metadata));
```

## JDBC / JPA

The Java agent instruments JDBC automatically and creates spans for each query with `db.statement`, `db.system`, `db.name` attributes.

**Key configurations:**

```bash
# Capture SQL statement in span (sanitized by default)
-Dotel.instrumentation.jdbc.statement-sanitizer.enabled=true   # default: sanitizes ? values

# Disable sanitization to see actual parameter values (caution: PII risk)
-Dotel.instrumentation.jdbc.statement-sanitizer.enabled=false
```

**Custom span wrapping a complex JPA operation:**

```java
@Repository
public class ProductRepository {
    private final Tracer tracer = GlobalOpenTelemetry.getTracer("com.myapp.products");

    @Autowired
    private EntityManager entityManager;

    public List<Product> searchProducts(String query, int page) {
        Span span = tracer.spanBuilder("product.search")
            .setAttribute("search.query", query)
            .setAttribute("search.page", page)
            .startSpan();
        try (Scope scope = span.makeCurrent()) {
            // JDBC spans for individual queries are auto-created inside this
            TypedQuery<Product> q = entityManager.createQuery(
                "SELECT p FROM Product p WHERE p.name LIKE :query", Product.class);
            q.setParameter("query", "%" + query + "%");
            q.setFirstResult(page * 20);
            q.setMaxResults(20);
            List<Product> results = q.getResultList();
            span.setAttribute("search.result_count", results.size());
            return results;
        } finally {
            span.end();
        }
    }
}
```

## Kafka

The Java agent auto-instruments KafkaProducer and KafkaConsumer. Manual Kafka spans:

**Spring Kafka listener with custom span:**

```java
import org.springframework.kafka.annotation.KafkaListener;
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Scope;

@Component
public class OrderEventConsumer {
    private final Tracer tracer = GlobalOpenTelemetry.getTracer("com.myapp.kafka");

    @KafkaListener(topics = "orders", groupId = "order-processor")
    public void onOrderEvent(ConsumerRecord<String, String> record) {
        // Agent creates a consumer span automatically
        // Add a child span for business logic
        Span span = tracer.spanBuilder("order.process")
            .setAttribute("order.partition", record.partition())
            .setAttribute("order.offset", record.offset())
            .startSpan();
        try (Scope scope = span.makeCurrent()) {
            processOrder(record.value());
        } catch (Exception e) {
            span.recordException(e);
            span.setStatus(StatusCode.ERROR);
            throw e;
        } finally {
            span.end();
        }
    }
}
```

## Agent Version Compatibility

| Agent version | SDK BOM version | Instrumentation artifacts version |
|---|---|---|
| v2.25.0 | 1.59.0 | 2.25.0-alpha |
| v2.x | 1.x (matching) | 2.x-alpha |

Always match the `-alpha` instrumentation artifact version to the agent version. Mismatches cause `NoClassDefFoundError` or silent no-ops.

## Lifecycle Logging

Structured log events correlated with OTel trace context using SLF4J + Logback (MDC).

```java
// logback.xml — include trace context in every log line
// (The OTel Java agent automatically populates MDC with trace_id and span_id)

// Example logback pattern:
// %d{ISO8601} [%thread] %-5level %logger{36} trace_id=%X{trace_id} span_id=%X{span_id} - %msg%n

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;

public class MyService {
    private static final Logger log = LoggerFactory.getLogger(MyService.class);

    // --- Service startup (Spring Boot: ApplicationReadyEvent) ---
    @EventListener(ApplicationReadyEvent.class)
    public void onStartup() {
        log.info("service starting version={} environment={}",
            System.getenv("APP_VERSION"),
            System.getenv("DEPLOYMENT_ENV"));
    }

    // --- Request lifecycle (Spring MVC interceptor) ---
    @Override
    public boolean preHandle(HttpServletRequest req, HttpServletResponse res, Object handler) {
        log.info("request received method={} path={}", req.getMethod(), req.getRequestURI());
        return true;
    }

    @Override
    public void afterCompletion(HttpServletRequest req, HttpServletResponse res, Object handler, Exception ex) {
        log.info("request completed method={} path={} status={}",
            req.getMethod(), req.getRequestURI(), res.getStatus());
    }

    // --- Graceful shutdown ---
    @PreDestroy
    public void onShutdown() {
        log.info("service shutting down");
        // Spring manages OTel shutdown via AutoConfiguration
    }
}
```

> When using the **javaagent**, `trace_id` and `span_id` are injected into SLF4J MDC automatically — no code change needed. The logback pattern `%X{trace_id}` outputs the current trace ID.

> For manual SDK setup (no agent), add the OTel log bridge dependency and configure `OpenTelemetryAppender` in logback.xml to bridge SLF4J logs to OTel.
