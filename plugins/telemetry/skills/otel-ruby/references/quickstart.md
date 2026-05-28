# Quick Start — Ruby OTel

> Last verified: 2026-03-23 | SDK: opentelemetry-sdk 1.10.0 / opentelemetry-exporter-otlp 0.32.0

> Run `ruby --version` — Ruby 3.1+ required for opentelemetry-sdk 1.10.x. If below 3.1, use the 0.x gem series (Ruby 2.7–3.0).

## Gemfile Setup

```ruby
# Gemfile
gem 'opentelemetry-sdk', '~> 1.10'
gem 'opentelemetry-exporter-otlp', '~> 0.32'
gem 'opentelemetry-instrumentation-all'   # auto-instrumentation for all installed libraries
```

```bash
bundle install
```

> **Why `opentelemetry-instrumentation-all`?** This meta-gem depends on all individual `opentelemetry-instrumentation-*` gems. `use_all()` in the configure block activates only the ones whose libraries are installed, so it is safe to include even if you use only a subset.

For per-library opt-in instead of `use_all()`:

```ruby
gem 'opentelemetry-instrumentation-rack'
gem 'opentelemetry-instrumentation-active_record'
gem 'opentelemetry-instrumentation-net_http'
```

## SDK Initialization

Place in `config/initializers/opentelemetry.rb` (Rails) or at the top of `config.ru` / `app.rb` (Sinatra, plain Ruby).

```ruby
# CORRECT — require order matters: sdk → exporter → instrumentation → configure
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'        # MUST be before configure
require 'opentelemetry/instrumentation/all'

OpenTelemetry::SDK.configure do |c|
  # service.name is read from OTEL_SERVICE_NAME automatically — do NOT set c.service_name in code
  # service.version has no dedicated env var; add in code if needed:
  c.resource = OpenTelemetry::SDK::Resources::Resource.create(
    'service.version' => '1.0.0'
  )
  c.use_all   # activates all installed opentelemetry-instrumentation-* gems
end
```

**Critical ordering rule:**

```ruby
# BAD — tracer obtained before configure; SDK is locked as no-op; configure is a no-op
tracer = OpenTelemetry.tracer_provider.tracer('my-service')
OpenTelemetry::SDK.configure { |c| c.use_all }   # too late — no effect

# GOOD — configure first, then get tracer
OpenTelemetry::SDK.configure { |c| c.use_all }
tracer = OpenTelemetry.tracer_provider.tracer('my-service')
```

## OTLP Exporter Configuration

The Ruby gem defaults to HTTP/protobuf on port 4318. Configure via environment variables — do not hardcode endpoints in source files.

```bash
# HTTP/protobuf (default — no protocol env var needed)
OTEL_SERVICE_NAME=my-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318

# gRPC opt-in (must also use port 4317)
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```

> **Protocol mismatch trap:** Setting `OTEL_EXPORTER_OTLP_PROTOCOL=grpc` but leaving the endpoint on port 4318 causes silent failure — the gem tries gRPC on port 4318 and gets HTTP/2 framing errors. When switching to gRPC, change both the protocol AND the port.

## Shutdown

**Production requirement:** Missing shutdown is the most common cause of lost spans in Ruby. The `BatchSpanProcessor` buffers spans in memory and must flush before the process exits. The `at_exit` hook is the minimum — **non-optional for production**. Puma and Sidekiq require server-specific hooks in addition.

```ruby
# Required: at_exit hook (works for all Ruby processes — minimum viable shutdown)
at_exit do
  OpenTelemetry.tracer_provider.shutdown
end

# Rails + Puma: also add to config/puma.rb (at_exit alone is not sufficient for Puma workers)
on_worker_shutdown do
  OpenTelemetry.tracer_provider.shutdown
end

# Sidekiq: also add to config/initializers/sidekiq.rb
Sidekiq.configure_server do |config|
  config.on(:shutdown) do
    OpenTelemetry.tracer_provider.shutdown
  end
end
```

> **Common mistake:** Using `Kernel.exit!` bypasses `at_exit` hooks. The SDK flush is skipped and the last batch of spans is lost. Use `exit` (not `exit!`) or add explicit shutdown before any `exit!` calls.

## Required Environment Variables

```bash
# Minimum required — see references/resource-attributes.md to resolve the correct service name
OTEL_SERVICE_NAME=my-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318

# Strongly recommended
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production,service.version=1.0.0
```

> `OTEL_SERVICE_NAME` is read automatically by the Ruby SDK. Do not set `c.service_name` in the configure block — it bypasses the env var and hardcodes the value.

## Post-Deploy Verification

```bash
# Confirm traces arrive
tsuga spans search --query "context.service.name:my-service" --max-results 5

# Confirm logs with trace correlation
tsuga logs search --query "context.service.name:my-service trace_id:*" --max-results 3

# Confirm metrics
tsuga metrics list --filter "service.name=my-service"
```

If no data: `tsuga-debug-no-data` skill.
If traces don't link across services: `tsuga-debug-missing-trace-propagation` skill.
