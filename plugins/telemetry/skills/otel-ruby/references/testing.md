# Telemetry Testing — Ruby

## In-Memory Exporter Setup

```ruby
require 'opentelemetry-sdk'
require 'opentelemetry/sdk/trace/export/in_memory_span_exporter'

module OTelTestHelper
  def setup_test_tracer
    @span_exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new(
      sampler: OpenTelemetry::SDK::Trace::Samplers::ALWAYS_ON
    )
    tracer_provider.add_span_processor(
      OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(@span_exporter)
    )
    OpenTelemetry.tracer_provider = tracer_provider
  end

  def finished_spans
    @span_exporter.finished_spans
  end
end
```

## Span Assertions

```ruby
RSpec.describe OrderService do
  include OTelTestHelper

  before(:each) { setup_test_tracer }
  after(:each)  { @span_exporter.reset! }

  it 'creates a SERVER root span' do
    subject.create_order(item: 'widget', quantity: 2)

    expect(finished_spans).not_to be_empty

    root_spans = finished_spans.reject { |s| s.parent_span_id && s.parent_span_id != "\x00" * 8 }
    expect(root_spans.length).to eq(1), "Expected 1 root span, got #{root_spans.length}"
    expect(root_spans.first.name).to eq('POST /orders')
    expect(root_spans.first.kind).to eq(:server)
  end

  it 'has no orphan CLIENT/PRODUCER spans' do
    subject.create_order(item: 'widget')

    orphans = finished_spans.select do |s|
      [:client, :producer].include?(s.kind) &&
        (!s.parent_span_id || s.parent_span_id == "\x00" * 8)
    end

    expect(orphans).to be_empty,
      "Found orphan spans: #{orphans.map(&:name).join(', ')}"
  end

  it 'error spans have status descriptions' do
    expect { subject.create_order(nil) }.to raise_error

    error_spans = finished_spans.select { |s| s.status.code == OpenTelemetry::Trace::Status::ERROR }
    error_spans.each do |span|
      expect(span.status.description).not_to be_empty,
        "ERROR span '#{span.name}' has no status description"
    end
  end

  it 'span names are low-cardinality templates' do
    subject.create_order(item: 'widget', user_id: 'user-123')

    uuid_pattern = /[0-9a-f]{8}-[0-9a-f]{4}/
    numeric_id_pattern = %r{/\d+}

    finished_spans.each do |span|
      expect(span.name).not_to match(uuid_pattern),
        "Span '#{span.name}' contains UUID — use template"
      expect(span.name).not_to match(numeric_id_pattern),
        "Span '#{span.name}' contains numeric ID — use template"
    end
  end
end
```
