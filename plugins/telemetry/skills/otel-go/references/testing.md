# Telemetry Testing — Go

## In-Memory Exporter Setup

```go
import (
    "go.opentelemetry.io/otel/sdk/trace"
    "go.opentelemetry.io/otel/sdk/trace/tracetest"
    sdkmetric "go.opentelemetry.io/otel/sdk/metric"
    "go.opentelemetry.io/otel/sdk/metric/metricdata"
)

func setupTestTracer(t *testing.T) (*tracetest.SpanRecorder, func()) {
    recorder := tracetest.NewSpanRecorder()
    tp := trace.NewTracerProvider(trace.WithSpanProcessor(recorder))
    otel.SetTracerProvider(tp)

    return recorder, func() {
        _ = tp.Shutdown(context.Background())
    }
}

func setupTestMeter(t *testing.T) (*sdkmetric.ManualReader, func()) {
    reader := sdkmetric.NewManualReader()
    mp := sdkmetric.NewMeterProvider(sdkmetric.WithReader(reader))
    otel.SetMeterProvider(mp)

    return reader, func() {
        _ = mp.Shutdown(context.Background())
    }
}
```

## Span Assertions

```go
func TestOrderServiceCreatesRootSpan(t *testing.T) {
    recorder, cleanup := setupTestTracer(t)
    defer cleanup()

    CreateOrder(context.Background(), Order{Item: "widget"})

    // recorder.Ended() returns []sdktrace.ReadOnlySpan — convert to SpanStubs for easier assertions
    spans := tracetest.SpanStubsFromReadOnlySpans(recorder.Ended())
    require.NotEmpty(t, spans, "expected at least one span")

    // Find root span
    var rootSpans []tracetest.SpanStub
    for _, s := range spans {
        if !s.Parent.IsValid() {
            rootSpans = append(rootSpans, s)
        }
    }
    require.Len(t, rootSpans, 1, "expected exactly 1 root span")

    root := rootSpans[0]
    assert.Equal(t, "POST /orders", root.Name)
    assert.Equal(t, trace.SpanKindServer, root.SpanKind)
}

func TestNoOrphanClientSpans(t *testing.T) {
    recorder, cleanup := setupTestTracer(t)
    defer cleanup()

    CreateOrder(context.Background(), Order{Item: "widget"})

    for _, span := range tracetest.SpanStubsFromReadOnlySpans(recorder.Ended()) {
        if span.SpanKind == trace.SpanKindClient || span.SpanKind == trace.SpanKindProducer {
            assert.True(t, span.Parent.IsValid(),
                "CLIENT/PRODUCER span %q has no parent — orphaned span", span.Name)
        }
    }
}

func TestErrorSpanHasDescription(t *testing.T) {
    recorder, cleanup := setupTestTracer(t)
    defer cleanup()

    _ = CreateOrderWithInvalidData(context.Background(), Order{})

    for _, span := range tracetest.SpanStubsFromReadOnlySpans(recorder.Ended()) {
        if span.Status.Code == codes.Error {
            assert.NotEmpty(t, span.Status.Description,
                "ERROR span %q has no status description", span.Name)
        }
    }
}

func TestSpanNamesAreTemplate(t *testing.T) {
    recorder, cleanup := setupTestTracer(t)
    defer cleanup()

    CreateOrder(context.Background(), Order{Item: "widget", UserID: "user-123"})

    uuidPattern := regexp.MustCompile(`[0-9a-f]{8}-[0-9a-f]{4}`)
    numericIDPattern := regexp.MustCompile(`/\d+`)

    for _, span := range tracetest.SpanStubsFromReadOnlySpans(recorder.Ended()) {
        assert.False(t, uuidPattern.MatchString(span.Name),
            "span name %q contains UUID — use template", span.Name)
        assert.False(t, numericIDPattern.MatchString(span.Name),
            "span name %q contains numeric ID — use template", span.Name)
    }
}
```

## Metric Assertions

```go
func TestRequestCounterHasUnit(t *testing.T) {
    reader, cleanup := setupTestMeter(t)
    defer cleanup()

    MakeRequest(context.Background(), "/orders")

    var data metricdata.ResourceMetrics
    _ = reader.Collect(context.Background(), &data)

    for _, sm := range data.ScopeMetrics {
        for _, m := range sm.Metrics {
            if strings.Contains(m.Name, "request") {
                assert.NotEmpty(t, m.Unit,
                    "metric %q has no unit", m.Name)
            }
        }
    }
}
```

## Auto-Instrumentation Verification

```go
func TestHTTPServerUsesCurrentSemconv(t *testing.T) {
    recorder, cleanup := setupTestTracer(t)
    defer cleanup()

    // Make a test HTTP request
    w := httptest.NewRecorder()
    req := httptest.NewRequest("GET", "/orders", nil)
    handler.ServeHTTP(w, req)

    stubs := tracetest.SpanStubsFromReadOnlySpans(recorder.Ended())
    serverSpans := filterByKind(stubs, trace.SpanKindServer)
    require.NotEmpty(t, serverSpans)

    attrs := serverSpans[0].Attributes
    attrMap := make(map[string]bool)
    for _, a := range attrs {
        attrMap[string(a.Key)] = true
    }

    assert.True(t, attrMap["http.request.method"],
        "expected http.request.method (current semconv)")
    assert.False(t, attrMap["http.method"],
        "found deprecated http.method — update instrumentation library")
}
```
