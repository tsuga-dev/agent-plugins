# Framework-Specific Recipes — Ruby

## Rails

Rails is the most common Ruby web framework. OTel integrates via Rack middleware and Rails-specific instrumentation. With the gems below, you get automatic spans for every inbound HTTP request (via Rack), controller action names and view rendering timing (via the Rails instrumentation), and a span per ActiveRecord query — all without writing any tracing code in your application layer.

```ruby
# Gemfile
gem 'opentelemetry-api', '~> 1.8'
gem 'opentelemetry-sdk', '~> 1.10'
gem 'opentelemetry-exporter-otlp', '~> 0.32'
gem 'opentelemetry-instrumentation-all'
```

```ruby
# config/initializers/opentelemetry.rb
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/all'

OpenTelemetry::SDK.configure do |c|
  # service.name is read from OTEL_SERVICE_NAME env var automatically — do not set c.service_name in code
  c.resource = OpenTelemetry::SDK::Resources::Resource.create(
    'service.version'              => Rails.application.config.version || '1.0.0',
    'deployment.environment.name'  => Rails.env,
  )

  c.use 'OpenTelemetry::Instrumentation::Rails'
  c.use 'OpenTelemetry::Instrumentation::Rack', {
    untraced_endpoints: ['/health', '/healthz', '/readyz'],
    allowed_request_headers: %w[x-request-id x-correlation-id],
  }
  c.use 'OpenTelemetry::Instrumentation::ActiveRecord'
  c.use 'OpenTelemetry::Instrumentation::Net::HTTP'
  c.use 'OpenTelemetry::Instrumentation::Redis'
  c.use 'OpenTelemetry::Instrumentation::Sidekiq'
end
```

**Controller with manual spans:**

Use `TRACER.in_span` when you want to track a discrete business-logic step within a controller action as its own span — for example, an external API call, a complex pricing calculation, or a multi-step validation that you want to measure and attribute separately from the parent HTTP span. For simple CRUD operations where ActiveRecord instrumentation already covers the database work, relying on auto-instrumentation is sufficient.

```ruby
class OrdersController < ApplicationController
  TRACER = OpenTelemetry.tracer_provider.tracer('my-service', '1.0.0')

  def create
    # Rails/Rack instrumentation creates the HTTP span automatically
    # Add business logic spans as children

    order = TRACER.in_span('order.validate') do |span|
      span.set_attribute('order.line_items', order_params[:items].size)
      validate_order!(order_params)
    end

    TRACER.in_span('order.persist') do |span|
      @order = Order.create!(order_params)
      span.set_attribute('order.id', @order.id.to_s)
    end

    render json: @order, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors }, status: :unprocessable_entity
  end

  private

  def order_params
    params.require(:order).permit(:user_id, items: [:product_id, :quantity])
  end
end
```

**ActiveJob (background jobs):**

The Sidekiq and ActiveJob auto-instrumentation covers job enqueue and overall execution timing, but the job body itself is opaque — all the work appears as a single undifferentiated span. Add `in_span` blocks around the meaningful steps inside `perform` (fetching records, calling external services, writing results) so you can see where time is actually spent and where failures originate.

```ruby
class ProcessOrderJob < ApplicationJob
  queue_as :default

  TRACER = OpenTelemetry.tracer_provider.tracer('my-service', '1.0.0')

  def perform(order_id)
    # ActiveJob instrumentation creates a job span automatically
    # Add child spans for subtasks
    TRACER.in_span('order.process') do |span|
      span.set_attribute('order.id', order_id.to_s)
      order = Order.find(order_id)
      fulfill_order(order)
    end
  end
end
```

## Sinatra

```ruby
# Gemfile
gem 'sinatra'
gem 'opentelemetry-api', '~> 1.8'
gem 'opentelemetry-sdk', '~> 1.10'
gem 'opentelemetry-exporter-otlp', '~> 0.32'
gem 'opentelemetry-instrumentation-rack'
gem 'opentelemetry-instrumentation-sinatra'
gem 'opentelemetry-instrumentation-net_http'
```

```ruby
# app.rb
require 'sinatra'
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/rack'
require 'opentelemetry/instrumentation/sinatra'
require 'opentelemetry/instrumentation/net_http'

# Configure OTel BEFORE Sinatra app setup
OpenTelemetry::SDK.configure do |c|
  # service.name is read from OTEL_SERVICE_NAME env var automatically — do not set c.service_name in code
  c.resource = OpenTelemetry::SDK::Resources::Resource.create(
    'deployment.environment.name' => ENV.fetch('RACK_ENV', 'development')
  )
  c.use 'OpenTelemetry::Instrumentation::Rack',
        untraced_endpoints: ['/health']
  c.use 'OpenTelemetry::Instrumentation::Sinatra'
  c.use 'OpenTelemetry::Instrumentation::Net::HTTP'
end

TRACER = OpenTelemetry.tracer_provider.tracer('sinatra-service', '1.0.0')

get '/users/:id' do
  content_type :json

  TRACER.in_span('db.get_user') do |span|
    span.set_attribute('user.id', params[:id])
    user = User.find(params[:id])
    { id: user.id, name: user.name }.to_json
  end
rescue ActiveRecord::RecordNotFound => e
  status 404
  { error: 'user not found' }.to_json
end

get '/health' do
  { status: 'ok' }.to_json
end
```

## Span Budget in Rails

| Request type | Spans created |
|---|---|
| HTTP request | Rack span (auto) + Rails controller span (auto) |
| Database query | ActiveRecord span per query (auto) |
| Redis call | Redis span (auto) |
| Sidekiq job | Job span (auto, in worker process) |
| Business logic | Manual `in_span` blocks |
| Helper methods | Skip — too granular |

## Error Handling Pattern

```ruby
tracer = OpenTelemetry.tracer_provider.tracer('my-service')

tracer.in_span('risky.operation') do |span|
  begin
    result = do_risky_work
    span.set_attribute('result.count', result.size)
    result
  rescue MyDomainError => e
    span.record_exception(e)
    span.status = OpenTelemetry::Trace::Status.error("domain error: #{e.message}")
    raise
  rescue StandardError => e
    span.record_exception(e)
    span.status = OpenTelemetry::Trace::Status.error(e.message)
    raise
  end
end
```

## Trace-Log Correlation in Rails

Add trace context to Rails logger output (see SKILL.md for full patterns):

```ruby
# config/initializers/logging.rb
Rails.logger = ActiveSupport::Logger.new($stdout)
Rails.logger.formatter = proc do |severity, time, progname, msg|
  ctx = OpenTelemetry::Trace.current_span.context
  fields = {
    time: time.iso8601(3),
    level: severity,
    message: msg,
  }
  if ctx.valid?
    fields[:trace_id] = ctx.hex_trace_id
    fields[:span_id]  = ctx.hex_span_id
  end
  fields.to_json + "\n"
end

## Lifecycle Logging

Structured log events correlated with OTel trace context.

```ruby
require 'opentelemetry'
require 'logger'
require 'json'

# JSON logger that injects OTel trace context
class OTelLogger
  def initialize(device = $stdout)
    @logger = Logger.new(device)
    @logger.formatter = method(:format_with_trace)
  end

  def format_with_trace(severity, _time, _progname, msg)
    span = OpenTelemetry::Trace.current_span
    ctx = span.context
    entry = { level: severity, message: msg.to_s }
    if ctx.valid?
      entry[:trace_id] = ctx.hex_trace_id
      entry[:span_id]  = ctx.hex_span_id
    end
    entry.merge!(@base_fields ||= {})
    JSON.generate(entry) + "\n"
  end

  def method_missing(method, *args, &block)
    @logger.send(method, *args, &block)
  end
end

logger = OTelLogger.new

# --- Service startup ---
def log_startup(logger)
  logger.info({
    event: "service_starting",
    version: ENV.fetch("APP_VERSION", "unknown"),
    environment: ENV.fetch("RACK_ENV", "unknown"),
    otlp_endpoint: ENV.fetch("OTEL_EXPORTER_OTLP_ENDPOINT", "not set"),
  }.to_json)
end

# --- Request lifecycle (Rack middleware) ---
class RequestLogger
  def initialize(app, logger:)
    @app, @logger = app, logger
  end

  def call(env)
    @logger.info({ event: "request_received", method: env["REQUEST_METHOD"], path: env["PATH_INFO"] }.to_json)
    status, headers, body = @app.call(env)
    @logger.info({ event: "request_completed", method: env["REQUEST_METHOD"], path: env["PATH_INFO"], status: status }.to_json)
    [status, headers, body]
  end
end

# --- Graceful shutdown ---
at_exit do
  logger.info({ event: "service_shutting_down" }.to_json)
  OpenTelemetry.tracer_provider.shutdown
  logger.info({ event: "otel_shutdown_complete" }.to_json)
end
```

> `ctx.hex_trace_id` returns the trace ID as a 32-char hex string. This correlates Ruby logs with traces in Tsuga's log search.
```

## Sinatra Microservice — End-to-End Recipe

Complete example: initialize exporter, instrument inbound/outbound HTTP, lifecycle, and shutdown.

```ruby
# Gemfile additions:
# gem 'opentelemetry-sdk'
# gem 'opentelemetry-exporter-otlp'
# gem 'opentelemetry-instrumentation-sinatra'
# gem 'opentelemetry-instrumentation-net_http'

require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/sinatra'
require 'opentelemetry/instrumentation/net_http'
require 'sinatra/base'
require 'net/http'

# Configure OTel SDK before Sinatra app loads
OpenTelemetry::SDK.configure do |c|
  # service.name is read from OTEL_SERVICE_NAME env var automatically — do not set c.service_name in code

  # OTLP exporter (configure endpoint via OTEL_EXPORTER_OTLP_ENDPOINT)
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      OpenTelemetry::Exporter::OTLP::Exporter.new
    )
  )

  # Auto-instrument Sinatra + outbound Net::HTTP
  c.use 'OpenTelemetry::Instrumentation::Sinatra'
  c.use 'OpenTelemetry::Instrumentation::Net::HTTP'
end

class MyApp < Sinatra::Base
  tracer = OpenTelemetry.tracer_provider.tracer('my-sinatra-service')

  get '/process' do
    # Inbound span created automatically by Sinatra instrumentation
    # Add custom business span
    tracer.in_span('process-request', attributes: { 'business.id' => params[:id] }) do |span|
      # Outbound HTTP — traceparent injected automatically by Net::HTTP instrumentation
      uri = URI('http://downstream-service/api/data')
      response = Net::HTTP.get_response(uri)

      span.set_attribute('downstream.status', response.code.to_i)
      { status: 'ok', data: response.body }.to_json
    end
  end
end

# Shutdown on process exit — CRITICAL for short-lived processes
at_exit do
  OpenTelemetry.tracer_provider.shutdown
end

MyApp.run!
```

**Notes:**
- `at_exit` shutdown is essential — missing it is the most common cause of "no spans exported"
- For Rack middleware (without Sinatra DSL), use `opentelemetry-instrumentation-rack`
- `BatchSpanProcessor` is correct for production; use `SimpleSpanProcessor` only for local debugging
- Context propagation for W3C traceparent is handled automatically by the Sinatra and Net::HTTP instrumentations
