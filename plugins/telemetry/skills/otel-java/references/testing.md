# Telemetry Testing — Java

## In-Memory Exporter Setup

```xml
<!-- pom.xml -->
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-sdk-testing</artifactId>
    <version>${opentelemetry.version}</version>
    <scope>test</scope>
</dependency>
```

```java
import io.opentelemetry.sdk.testing.junit5.OpenTelemetryExtension;
import io.opentelemetry.sdk.trace.data.SpanData;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.trace.StatusCode;
import org.junit.jupiter.api.extension.RegisterExtension;

class OrderServiceTest {
    @RegisterExtension
    static final OpenTelemetryExtension otelTesting = OpenTelemetryExtension.create();

    @Test
    void createsServerRootSpan() {
        orderService.createOrder(new Order("widget", 2));

        List<SpanData> spans = otelTesting.getSpans();
        assertFalse(spans.isEmpty());

        List<SpanData> rootSpans = spans.stream()
            .filter(s -> !s.getParentSpanContext().isValid())
            .collect(toList());

        assertEquals(1, rootSpans.size(), "Expected 1 root span");
        assertEquals("POST /orders", rootSpans.get(0).getName());
        assertEquals(SpanKind.SERVER, rootSpans.get(0).getKind());
    }

    @Test
    void noOrphanClientSpans() {
        orderService.createOrder(new Order("widget", 2));

        otelTesting.getSpans().stream()
            .filter(s -> s.getKind() == SpanKind.CLIENT || s.getKind() == SpanKind.PRODUCER)
            .forEach(span -> assertTrue(
                span.getParentSpanContext().isValid(),
                "CLIENT/PRODUCER span '" + span.getName() + "' has no parent — orphaned span"
            ));
    }

    @Test
    void errorSpanHasDescription() {
        assertThrows(Exception.class, () -> orderService.createOrder(null));

        otelTesting.getSpans().stream()
            .filter(s -> s.getStatus().getStatusCode() == StatusCode.ERROR)
            .forEach(span -> assertFalse(
                span.getStatus().getDescription().isEmpty(),
                "ERROR span '" + span.getName() + "' has no status description"
            ));
    }

    @Test
    void spanNamesAreTemplate() {
        orderService.createOrder(new Order("widget", 2));

        Pattern uuidPattern = Pattern.compile("[0-9a-f]{8}-[0-9a-f]{4}");
        Pattern numericIdPattern = Pattern.compile("/\\d+");

        otelTesting.getSpans().forEach(span -> {
            assertFalse(uuidPattern.matcher(span.getName()).find(),
                "Span '" + span.getName() + "' contains UUID — use template");
            assertFalse(numericIdPattern.matcher(span.getName()).find(),
                "Span '" + span.getName() + "' contains numeric ID — use template");
        });
    }
}
```

## Metric Assertions

```java
@Test
void requestCounterHasUnit() {
    makeRequest("/orders");

    List<MetricData> metrics = otelTesting.getMetrics();
    metrics.stream()
        .filter(m -> m.getName().contains("request"))
        .forEach(m -> assertFalse(
            m.getUnit().isEmpty(),
            "Metric '" + m.getName() + "' has no unit"
        ));
}
```
