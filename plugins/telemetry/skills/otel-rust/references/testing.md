# Telemetry Testing — Rust

## In-Memory Exporter Setup

```rust
use opentelemetry_sdk::trace::InMemorySpanExporterBuilder;
use opentelemetry_sdk::trace::InMemorySpanExporter;
use opentelemetry_sdk::trace::SdkTracerProvider;
use opentelemetry::global;

pub fn setup_test_tracer() -> InMemorySpanExporter {
    let exporter = InMemorySpanExporterBuilder::new().build();
    let provider = SdkTracerProvider::builder()
        .with_simple_exporter(exporter.clone())
        .build();
    global::set_tracer_provider(provider);
    exporter
}
```

## Span Assertions

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use opentelemetry::trace::SpanKind;
    use opentelemetry::trace::Status;
    use regex::Regex;

    #[tokio::test]
    async fn creates_server_root_span() {
        let exporter = setup_test_tracer();

        create_order(Order { item: "widget".to_string() }).await;

        let spans = exporter.get_finished_spans().unwrap();
        assert!(!spans.is_empty(), "Expected at least one span");

        let root_spans: Vec<_> = spans.iter()
            .filter(|s| !s.parent_span_id.is_valid())
            .collect();

        assert_eq!(root_spans.len(), 1, "Expected 1 root span");
        assert_eq!(root_spans[0].name, "POST /orders");
        assert_eq!(root_spans[0].span_kind, SpanKind::Server);
    }

    #[tokio::test]
    async fn no_orphan_client_spans() {
        let exporter = setup_test_tracer();

        create_order(Order { item: "widget".to_string() }).await;

        let spans = exporter.get_finished_spans().unwrap();
        for span in &spans {
            if span.span_kind == SpanKind::Client || span.span_kind == SpanKind::Producer {
                assert!(
                    span.parent_span_id.is_valid(),
                    "CLIENT/PRODUCER span '{}' has no parent — orphaned span",
                    span.name
                );
            }
        }
    }

    #[tokio::test]
    async fn span_names_are_templates() {
        let exporter = setup_test_tracer();

        create_order(Order { item: "widget".to_string() }).await;

        let uuid_pattern = Regex::new(r"[0-9a-f]{8}-[0-9a-f]{4}").unwrap();
        let numeric_id = Regex::new(r"/\d+").unwrap();

        for span in exporter.get_finished_spans().unwrap() {
            assert!(!uuid_pattern.is_match(&span.name),
                "Span '{}' contains UUID — use template", span.name);
            assert!(!numeric_id.is_match(&span.name),
                "Span '{}' contains numeric ID — use template", span.name);
        }
    }
}
```
