# Telemetry Testing — Python

How to write tests that verify your OTel instrumentation emits the correct telemetry.

## In-Memory Exporter Setup

```python
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import InMemoryMetricReader

import pytest

@pytest.fixture
def span_exporter():
    exporter = InMemorySpanExporter()
    provider = TracerProvider()
    provider.add_span_processor(SimpleSpanProcessor(exporter))
    # Set as global provider
    from opentelemetry import trace
    trace.set_tracer_provider(provider)
    yield exporter
    exporter.clear()

@pytest.fixture
def metric_reader():
    reader = InMemoryMetricReader()
    provider = MeterProvider(metric_readers=[reader])
    from opentelemetry import metrics
    metrics.set_meter_provider(provider)
    yield reader
```

## Span Assertions

```python
def test_order_service_creates_root_span(span_exporter):
    # Exercise the code under test
    create_order({"item": "widget", "quantity": 2})

    spans = span_exporter.get_finished_spans()

    # Assert: at least one span
    assert len(spans) > 0

    # Assert: root span exists (no parent)
    root_spans = [s for s in spans if s.parent is None]
    assert len(root_spans) == 1, f"Expected 1 root span, got {len(root_spans)}"

    root = root_spans[0]
    assert root.name == "POST /orders"
    assert root.kind == trace.SpanKind.SERVER

def test_no_orphan_client_spans(span_exporter):
    create_order({"item": "widget", "quantity": 2})
    spans = span_exporter.get_finished_spans()

    for span in spans:
        if span.kind in (trace.SpanKind.CLIENT, trace.SpanKind.PRODUCER):
            assert span.parent is not None, \
                f"CLIENT/PRODUCER span '{span.name}' has no parent — orphaned span"

def test_error_span_has_status(span_exporter):
    with pytest.raises(Exception):
        create_order_with_invalid_data({})

    spans = span_exporter.get_finished_spans()
    error_spans = [s for s in spans if s.status.status_code == trace.StatusCode.ERROR]

    for span in error_spans:
        assert span.status.description, \
            f"ERROR span '{span.name}' has no status description"

def test_span_names_are_low_cardinality(span_exporter):
    import re
    # Heuristic: span names should not contain numeric IDs or UUIDs
    uuid_pattern = re.compile(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
    numeric_id_pattern = re.compile(r'/\d+')

    create_order({"item": "widget"})
    spans = span_exporter.get_finished_spans()

    for span in spans:
        assert not uuid_pattern.search(span.name), \
            f"Span name '{span.name}' contains UUID — use a template instead"
        assert not numeric_id_pattern.search(span.name), \
            f"Span name '{span.name}' contains numeric ID — use a template"

def test_internal_span_count(span_exporter):
    create_order({"item": "widget"})
    spans = span_exporter.get_finished_spans()

    internal_spans = [s for s in spans if s.kind == trace.SpanKind.INTERNAL]
    assert len(internal_spans) < 10, \
        f"Too many INTERNAL spans ({len(internal_spans)}) — consider reducing instrumentation depth"
```

## Metric Assertions

```python
def test_request_counter_has_units(metric_reader):
    make_request("/orders")

    metrics_data = metric_reader.get_metrics_data()
    counters = [m for rm in metrics_data.resource_metrics
                for sm in rm.scope_metrics
                for m in sm.metrics
                if "request" in m.name.lower()]

    for counter in counters:
        assert counter.unit, f"Metric '{counter.name}' has no unit"

def test_no_high_cardinality_metric_attributes(metric_reader):
    # Make multiple requests with different user IDs
    for i in range(10):
        make_request("/orders", user_id=f"user-{i}")

    metrics_data = metric_reader.get_metrics_data()
    for rm in metrics_data.resource_metrics:
        for sm in rm.scope_metrics:
            for metric in sm.metrics:
                for dp in (metric.data.data_points if hasattr(metric.data, 'data_points') else []):
                    assert "user_id" not in dp.attributes, \
                        f"Metric '{metric.name}' has user_id as dimension — unbounded cardinality"
                    assert "user.id" not in dp.attributes, \
                        f"Metric '{metric.name}' has user.id as dimension — unbounded cardinality"
```

## Auto-Instrumentation Verification

Auto-instrumented libraries may emit outdated semconv attribute names. Write integration tests to catch mismatches:

```python
def test_http_server_uses_current_semconv(span_exporter):
    response = client.get("/orders")

    spans = span_exporter.get_finished_spans()
    server_spans = [s for s in spans if s.kind == trace.SpanKind.SERVER]
    assert len(server_spans) > 0

    span = server_spans[0]
    attrs = dict(span.attributes)

    # Check for current semconv (not deprecated names)
    assert "http.request.method" in attrs, \
        "Expected http.request.method (current semconv); got: " + str(list(attrs.keys()))
    assert "http.method" not in attrs, \
        "Found deprecated http.method — update instrumentation library"
```
