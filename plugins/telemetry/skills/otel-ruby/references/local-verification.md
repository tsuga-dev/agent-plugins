# Local Verification — Ruby

## Overview

Before routing telemetry to a production collector, verify Ruby instrumentation by printing spans to stdout using `ConsoleSpanExporter`. The Ruby SDK Configurator supports `OTEL_TRACES_EXPORTER=console` — it automatically creates a `ConsoleSpanExporter` wrapped in a `SimpleSpanProcessor`. You can also configure the exporter explicitly in the `OpenTelemetry::SDK.configure` block. For scripts and short-lived processes, calling `OpenTelemetry.tracer_provider.shutdown` before exit is required to avoid dropped spans.

## Console Span Exporter

`ConsoleSpanExporter` is included in the `opentelemetry-sdk` gem. Pair it with `SimpleSpanProcessor` for synchronous, per-span output.

```ruby
require "opentelemetry/sdk"

OpenTelemetry::SDK.configure do |c|
  # service.name is read from OTEL_SERVICE_NAME env var automatically
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
      OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
    )
  )
end

tracer = OpenTelemetry.tracer_provider.tracer("my-service")

tracer.in_span("my-operation") do |span|
  span.set_attribute("example.key", "value")
  do_work
end
```

Each span is printed as a formatted Ruby hash containing trace ID, span ID, parent span ID, name, kind, attributes, status, and timing.

The hash includes keys: `name`, `trace_id`, `span_id`, `parent_span_id`, `kind`, `start_timestamp`, `end_timestamp`, `attributes`, `status`, and `events`. Output uses `pp`-style Ruby hash syntax, not JSON.

## SimpleSpanProcessor vs BatchSpanProcessor

| | `SimpleSpanProcessor` | `BatchSpanProcessor` |
|---|---|---|
| Export timing | Synchronous, on span end | Async, background thread |
| Local testing | Preferred — spans appear immediately | Requires `shutdown` to flush |
| Production | Not recommended — adds overhead per span | Correct choice |

Use `SimpleSpanProcessor` with `ConsoleSpanExporter` for all local development and testing. Switch to `BatchSpanProcessor` with an OTLP exporter in production configuration.

## Short-Lived Processes and Scripts

Ruby scripts that exit quickly will lose spans queued in `BatchSpanProcessor` unless `shutdown` is called. Even with `SimpleSpanProcessor`, calling `shutdown` is good practice to ensure metric readers and other SDK components flush cleanly.

```ruby
require "opentelemetry/sdk"

OpenTelemetry::SDK.configure do |c|
  # service.name is read from OTEL_SERVICE_NAME env var automatically
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
      OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
    )
  )
end

tracer = OpenTelemetry.tracer_provider.tracer("my-script")

begin
  tracer.in_span("etl.run") do |span|
    process_records
  end
ensure
  # Flush and release SDK resources before process exits
  OpenTelemetry.tracer_provider.shutdown
end
```

For Rake tasks or one-off jobs, wrap the entire task body in a `begin/ensure` block to guarantee shutdown runs even if an exception is raised.

For simple scripts, `at_exit { OpenTelemetry.tracer_provider.shutdown }` is a shorter alternative, but it does not run when the process is killed with `SIGKILL`. The `begin/ensure` pattern is more reliable for jobs that may be interrupted by deployment systems.

## OTEL_TRACES_EXPORTER Environment Variable

The Ruby SDK Configurator handles `OTEL_TRACES_EXPORTER=console` natively. When set, it creates a `ConsoleSpanExporter` wrapped in a `SimpleSpanProcessor` — no code changes are needed:

```bash
OTEL_TRACES_EXPORTER=console OTEL_SERVICE_NAME=my-service ruby app.rb
```

```ruby
# app.rb — no exporter configuration needed; the env var does it
require "opentelemetry/sdk"

OpenTelemetry::SDK.configure do |c|
  # service.name is read from OTEL_SERVICE_NAME env var automatically
  c.use_all
end
```

When `OTEL_TRACES_EXPORTER` is unset or `otlp`, the SDK uses the OTLP exporter with `BatchSpanProcessor` (requires `opentelemetry-exporter-otlp` gem and its require).

## Local Collector with Debug Exporter

Run `otelcol-contrib` locally to validate the full OTLP export path. The `debug` exporter prints every received span and metric with full attribute detail.

```yaml
# otelcol-config.yaml — local debug collector
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

exporters:
  debug:
    verbosity: detailed

service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [debug]
    metrics:
      receivers: [otlp]
      exporters: [debug]
```

Point the Ruby OTLP exporter at it:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 \
OTEL_SERVICE_NAME=my-service \
ruby app.rb
```

The Ruby OTLP exporter uses HTTP/protobuf on port 4318 exclusively. Do not use port 4317 — the Ruby exporter cannot speak gRPC.
