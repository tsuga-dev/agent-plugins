# Auto-Instrumentation — Ruby

## Overview

The `opentelemetry-instrumentation-all` gem bundles all maintained auto-instrumentation packages for Ruby. When enabled via `c.use_all` or `c.use 'InstrumentationName'` in the SDK configure block, it patches supported libraries at load time.

## Installation

```ruby
# Gemfile
gem 'opentelemetry-api', '~> 1.8'
gem 'opentelemetry-sdk', '~> 1.10'
gem 'opentelemetry-exporter-otlp', '~> 0.32'
gem 'opentelemetry-instrumentation-all'  # bundles all instrumentations
```

```bash
bundle install
```

## Setup

```ruby
# config/initializers/opentelemetry.rb (Rails)
# or top of app.rb (Sinatra)
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/all'

OpenTelemetry::SDK.configure do |c|
  # service.name is read from OTEL_SERVICE_NAME env var automatically — do not set c.service_name in code
  c.resource = OpenTelemetry::SDK::Resources::Resource.create(
    'service.version'              => '1.0.0',
    'deployment.environment.name'  => ENV.fetch('RAILS_ENV', 'development'),
  )
  c.use_all  # enable all bundled instrumentations
end
```

**Critical:** `OpenTelemetry::SDK.configure` must run before any instrumented library is loaded or used. In Rails, place this in an initializer that runs early (before Rack, ActiveRecord, etc.).

## Selectively Enabling Instrumentations

```ruby
OpenTelemetry::SDK.configure do |c|
  # service.name is read from OTEL_SERVICE_NAME env var automatically — do not set c.service_name in code

  # Enable only specific instrumentations
  c.use 'OpenTelemetry::Instrumentation::Rack'
  c.use 'OpenTelemetry::Instrumentation::Rails'
  c.use 'OpenTelemetry::Instrumentation::ActiveRecord'
  c.use 'OpenTelemetry::Instrumentation::HttpClient'
  c.use 'OpenTelemetry::Instrumentation::Redis'
  c.use 'OpenTelemetry::Instrumentation::Sidekiq'

  # With configuration options
  c.use 'OpenTelemetry::Instrumentation::Rack', {
    allowed_request_headers: %w[X-Correlation-Id],
    allowed_response_headers: %w[X-Request-Id],
    untraced_endpoints: ['/health', '/metrics'],
  }
end
```

## What Gets Covered Automatically

| Library | Gem |
|---|---|
| Rack (HTTP framework base) | `opentelemetry-instrumentation-rack` |
| Rails (Action Controller, Active Record, Action Mailer) | `opentelemetry-instrumentation-rails` |
| Sinatra | `opentelemetry-instrumentation-sinatra` |
| Net::HTTP (outbound) | `opentelemetry-instrumentation-net_http` |
| Faraday | `opentelemetry-instrumentation-faraday` |
| Redis | `opentelemetry-instrumentation-redis` |
| Sidekiq | `opentelemetry-instrumentation-sidekiq` |
| ActiveJob | `opentelemetry-instrumentation-active_job` |
| pg (PostgreSQL) | `opentelemetry-instrumentation-pg` |
| mysql2 | `opentelemetry-instrumentation-mysql2` |
| MongoDB (Mongo Ruby driver) | `opentelemetry-instrumentation-mongo` |
| gRPC | `opentelemetry-instrumentation-grpc` |
| Kafka (ruby-kafka) | `opentelemetry-instrumentation-ruby_kafka` |

> **Note:** HTTParty does not have its own instrumentation gem. HTTParty uses Net::HTTP under the hood, so it is covered automatically by `opentelemetry-instrumentation-net_http`.

## What Needs Manual Instrumentation

Auto-instrumentation does not cover:

- Business logic spans (e.g., `order.validate`, `checkout.process`)
- Background jobs beyond the framework wrapper — Sidekiq instrumentation creates a job span but not sub-task spans
- Custom protocols or internal RPCs not using a supported HTTP/gRPC library
- Rake tasks — `configure` runs in the Rails context, but Rake tasks may not have a TracerProvider set up

## Manual Spans Alongside Auto-Instrumentation

```ruby
tracer = OpenTelemetry.tracer_provider.tracer('my-service', '1.0.0')

class OrdersController < ApplicationController
  def create
    # Rails request span created automatically by instrumentation
    # Add a child span for business logic
    tracer.in_span('order.validate') do |span|
      span.set_attribute('order.items', params[:items].count)
      validate_order!(order_params)
    end

    tracer.in_span('order.persist') do |span|
      @order = Order.create!(order_params)
      span.set_attribute('order.id', @order.id)
    end

    render json: @order, status: :created
  end
end
```

## Protocol Note

The `opentelemetry-exporter-otlp` Ruby gem uses **HTTP/protobuf on port 4318** exclusively. There is no published gRPC exporter gem for Ruby.

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
```

Do not set `OTEL_EXPORTER_OTLP_ENDPOINT` to port 4317 — that port expects gRPC framing and the Ruby HTTP exporter will fail.

## Verifying Auto-Instrumentation Is Active

```bash
# Make a request, then:
tsuga spans search --query "context.service.name:my-service" --max-results 5
# Look for spans like "GET /users/:id", "ActiveRecord SELECT", "Redis GET"
```
