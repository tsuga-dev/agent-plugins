# Distributed Context Propagation — Ruby

> Last verified: 2026-03-23 | SDK: opentelemetry-sdk 1.10.0 / opentelemetry-exporter-otlp 0.32.0

## Overview

Trace context must be explicitly propagated across service boundaries. The W3C TraceContext headers (`traceparent`, `tracestate`) carry the trace ID and span ID between services. With auto-instrumentation (`c.use_all`), HTTP propagation for inbound Rack/Rails requests and outbound Net::HTTP/Faraday calls is automatic. For custom transports, explicit extract/inject is required.

> **Async messaging propagation (Kafka, Sidekiq):** See [async-messaging.md](async-messaging.md) — covers the span Links model, manual inject/extract into message headers and Sidekiq job args, and auto-instrumentation coverage.

## Inbound: Server Context Extraction

**Auto-instrumentation (Rack/Rails):** Fully automatic. The Rack instrumentation reads `traceparent` from incoming HTTP headers and creates a child span for the request. No code changes needed.

**Manual extraction (custom server or transport):**

```ruby
require 'opentelemetry'

def handle_request(env)
  # Rack env has HTTP headers as HTTP_* keys
  parent_ctx = OpenTelemetry.propagation.extract(
    env,
    getter: OpenTelemetry::Common::Propagation.rack_env_getter
  )

  tracer = OpenTelemetry.tracer_provider.tracer('my-service')
  tracer.in_span('handle.request', with_parent: parent_ctx) do |span|
    span.set_attribute('http.method', env['REQUEST_METHOD'])
    yield
  end
end
```

**Rack middleware (manual):**

```ruby
class OtelMiddleware
  def initialize(app)
    @app    = app
    @tracer = OpenTelemetry.tracer_provider.tracer('my-service')
  end

  def call(env)
    parent_ctx = OpenTelemetry.propagation.extract(
      env,
      getter: OpenTelemetry::Common::Propagation.rack_env_getter
    )

    @tracer.in_span('http.request', with_parent: parent_ctx) do |span|
      span.set_attribute('http.method', env['REQUEST_METHOD'])
      span.set_attribute('http.target', env['PATH_INFO'])

      status, headers, body = @app.call(env)
      span.set_attribute('http.status_code', status)
      [status, headers, body]
    end
  end
end
```

## Outbound: Client Context Injection

**Auto-instrumentation (Net::HTTP, Faraday):** Automatic when instrumentation is enabled via `c.use_all`.

**Manual injection with Net::HTTP:**

```ruby
require 'net/http'
require 'opentelemetry'

def call_downstream(uri_string)
  uri     = URI(uri_string)
  headers = {}
  OpenTelemetry.propagation.inject(headers)   # injects traceparent, tracestate

  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
    req = Net::HTTP::Get.new(uri)
    headers.each { |k, v| req[k] = v }
    http.request(req)
  end
end
```

**Manual injection with Faraday:**

```ruby
require 'faraday'
require 'opentelemetry'

def call_service(url)
  headers = {}
  OpenTelemetry.propagation.inject(headers)
  Faraday.get(url, nil, headers)
end
```

## Anti-Pattern: Do Not Merge Separate Workflows

```ruby
tracer = OpenTelemetry.tracer_provider.tracer('my-service')

# WRONG — consumer appears as child of producer HTTP request; merges unrelated traces
tracer.in_span('job.process', with_parent: extracted_ctx) do |span|
  # ...
end

# CORRECT — new root span; use span Links for cross-trace navigation
# See async-messaging.md for the full Links pattern
tracer.in_span('job.process') do |span|
  # span has no parent — it is a new root trace
  do_work
end
```

## Configuring Propagators

The Ruby SDK defaults to W3C TraceContext + Baggage. Use the default for all new services. Add `b3` only when interoperating with Zipkin-instrumented services or Istio/Envoy meshes configured for B3.

```ruby
# Default (no configuration needed for W3C TraceContext + Baggage)
OpenTelemetry::SDK.configure do |c|
  c.use_all
end

# Explicit propagator configuration (e.g., add B3 for legacy interop)
OpenTelemetry::SDK.configure do |c|
  c.propagators = [
    OpenTelemetry::Trace::Propagation::TraceContext.text_map_propagator,
    OpenTelemetry::Baggage::Propagation::TextMapPropagator.new
  ]
  c.use_all
end
```

## Tsuga Trace Continuity Validation

After instrumenting propagation, verify parent/child linkage:

```bash
tsuga spans search --query "context.service.name:<caller-service>" --max-results 5
# Note traceId values from results

tsuga spans search --query "context.service.name:<callee-service> traceId:<trace-id>"
# parentSpanId on callee spans must match spanId from caller spans
```
