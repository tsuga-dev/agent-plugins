# Endpoint, Protocol, and Troubleshooting — Ruby

> Last verified: 2026-03-23 | SDK: opentelemetry-sdk 1.10.0 / opentelemetry-exporter-otlp 0.32.0

## OTLP Protocol Reference

| Protocol | Port | Path auto-appended by SDK? | Notes |
|---|---|---|---|
| OTLP/HTTP | 4318 | Yes (`/v1/traces`, `/v1/metrics`, `/v1/logs`) | Default and only transport for Ruby gem |

> **Important:** The `opentelemetry-exporter-otlp` Ruby gem supports **HTTP/protobuf only** (port 4318). There is no published gRPC exporter gem for Ruby. Always use port 4318 with the Ruby exporter. Using port 4317 (the gRPC port) will fail because the collector expects gRPC framing on that port.

## Tsuga Endpoint Configuration

**HTTP/protobuf (default — no extra gem required):**

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://ingest.<region>.tsuga.cloud:443
OTEL_EXPORTER_OTLP_HEADERS=tsuga-ingestion-key=<your-key>
# No protocol env var needed — HTTP is the default
```

The gem appends `/v1/traces` automatically when `OTEL_EXPORTER_OTLP_ENDPOINT` is set.

**Programmatic HTTP configuration:**

```ruby
require 'opentelemetry/exporter/otlp'

OpenTelemetry::SDK.configure do |c|
  # service.name is read from OTEL_SERVICE_NAME env var automatically
  # To determine the correct service name, see `references/resource-attributes.md` → **Resolve resource attribute values**.
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      OpenTelemetry::Exporter::OTLP::Exporter.new(
        endpoint: 'https://ingest.<region>.tsuga.cloud:443/v1/traces',
        headers: { 'tsuga-ingestion-key' => ENV.fetch('TSUGA_INGESTION_KEY') },
      )
    )
  )
  c.use_all
end
```

> **Note:** The Ruby SDK only ships an HTTP/protobuf OTLP exporter (`opentelemetry-exporter-otlp`). There is no published `opentelemetry-exporter-otlp-grpc` gem. gRPC transport is not available for Ruby — use HTTP/protobuf (the default) for all Ruby services.

## Common Issues

### No spans arriving

1. **Default protocol on wrong port:** Using `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317` with no protocol set — the gem defaults to HTTP/protobuf and tries to POST to `http://localhost:4317/v1/traces`. Port 4317 expects gRPC — connection will fail or receive unexpected HTTP/2 frames.
2. **`require 'opentelemetry/exporter/otlp'` missing:** Without this require before `configure`, the exporter is not available and falls back to noop.
3. **`configure` is a no-op:** If `OpenTelemetry.tracer_provider.tracer(...)` is called before `configure`, the SDK is locked in as noop. The configure block runs but has no effect.

### Protocol/port mismatch

```bash
# WRONG — Ruby HTTP exporter talking to gRPC port
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317  # gRPC port — will fail

# CORRECT — Ruby only supports HTTP/protobuf
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
```

### SSL/TLS errors when connecting to Tsuga

The Tsuga endpoint uses TLS on port 443. The Ruby Net::HTTP-based exporter uses system CA certificates:

```ruby
# If system CAs are missing or outdated:
# macOS: brew install openssl
# Ubuntu: apt-get install ca-certificates

# Or specify CA cert manually:
OpenTelemetry::Exporter::OTLP::Exporter.new(
  endpoint: 'https://ingest.<region>.tsuga.cloud:443/v1/traces',
  ssl_verify_peer: true,
  # ssl_ca_cert: '/path/to/ca.crt',  # if needed
  headers: { 'tsuga-ingestion-key' => ENV.fetch('TSUGA_INGESTION_KEY') },
)
```

### Spans truncated / missing after Sidekiq worker exit

Sidekiq workers run as long-lived processes. Ensure spans are flushed when the worker shuts down:

```ruby
# config/initializers/opentelemetry.rb
Sidekiq.configure_server do |config|
  config.on(:shutdown) do
    OpenTelemetry.tracer_provider.shutdown
  end
end
```

### Debug mode

```bash
OTEL_LOG_LEVEL=debug bundle exec rails server
# Shows: exporter URL, headers, span creation, export results
```

## Shutdown / Flush

The Ruby SDK's `BatchSpanProcessor` buffers spans and exports on a schedule (default 5 seconds). On process exit, the SDK should flush remaining spans.

**Automatic shutdown (recommended):**

The SDK automatically registers an `at_exit` hook when configured. This flushes spans on normal process exit.

**Manual shutdown:**

```ruby
at_exit do
  OpenTelemetry.tracer_provider.shutdown
end
```

**Rails Puma server:**

```ruby
# config/puma.rb
on_worker_shutdown do
  OpenTelemetry.tracer_provider.shutdown
end
```

**Sidekiq:**

```ruby
Sidekiq.configure_server do |config|
  config.on(:shutdown) do
    OpenTelemetry.tracer_provider.shutdown
  end
end
```

**Common shutdown mistakes:**

- Not calling `shutdown` in Puma worker processes — Puma forks workers; each fork needs its own shutdown handler
- Calling `shutdown` before all request fibers complete — can truncate in-flight spans
- Using `Kernel.exit!` (bypasses `at_exit` hooks) instead of `exit` — the at_exit flush is skipped

## Resilience: Collector Unavailable

When the OTLP collector is unreachable, the Ruby OTel SDK does **not** raise exceptions to application code. The `BatchSpanProcessor` retries with backoff; spans are dropped when the buffer fills. The service remains operational.

**Default behavior:** `OTLP::Exporter` retries on network failure. Export errors are logged to the OTel logger (default: `$stderr`), not raised.

**Conditional setup:**

```ruby
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'

OpenTelemetry::SDK.configure do |c|
  # service.name is read from OTEL_SERVICE_NAME env var automatically

  endpoint = ENV['OTEL_EXPORTER_OTLP_ENDPOINT']
  if endpoint
    c.add_span_processor(
      OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
        OpenTelemetry::Exporter::OTLP::Exporter.new
      )
    )
  end
  # If no endpoint: SDK configured with no exporter — functional no-op
end
```

**Disable OTel:**
```bash
OTEL_SDK_DISABLED=true ruby app.rb
```

**Rails:** OTel is initialized in an initializer; if the collector is down, Rails boots and serves normally. Export failures appear only in logs.
