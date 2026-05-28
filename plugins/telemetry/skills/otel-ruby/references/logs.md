# Logs — Ruby OTel

> Last verified: 2026-03-23 | SDK: opentelemetry-sdk 1.10.0 / opentelemetry-exporter-otlp 0.32.0
>
> **Log bridge status:** No official OTel log bridge gem for Ruby as of early 2026. The Ruby `opentelemetry-logs-sdk` is in Development status. Suitable for instrumentation tasks; validate stability for your production use case. The manual trace_id injection + filelog receiver path is the stable alternative.

## Production Path for Ruby Logs

1. Extract `trace_id` and `span_id` from the current span context inside your log formatter
2. Emit structured JSON logs to stdout
3. Configure the OTel Collector `filelog` receiver to collect stdout JSON and forward via OTLP

This gives logs full trace correlation without requiring a stable log bridge gem.

## Manual Trace Context Injection

Extract context from `OpenTelemetry::Trace.current_span.context`. The context is valid only when a span is active (returns a no-op span context otherwise — check `ctx.valid?` before using the IDs).

### stdlib Logger

```ruby
require 'logger'
require 'json'
require 'opentelemetry'

logger = Logger.new($stdout)
logger.formatter = proc do |severity, datetime, progname, msg|
  ctx = OpenTelemetry::Trace.current_span.context
  fields = {
    level:   severity,
    time:    datetime.iso8601(3),
    message: msg.is_a?(String) ? msg : msg.inspect
  }
  if ctx.valid?
    fields[:trace_id]    = ctx.hex_trace_id
    fields[:span_id]     = ctx.hex_span_id
    fields[:trace_flags] = ctx.trace_flags.to_i
  end
  JSON.generate(fields) + "\n"
end

# Usage
logger.info('order placed')
# Output: {"level":"INFO","time":"2026-03-23T10:00:00.000Z","message":"order placed","trace_id":"abc123...","span_id":"def456...","trace_flags":1}
```

### Ougai

```ruby
# Gemfile: gem 'ougai'
require 'ougai'
require 'opentelemetry'

class OtelAwareLogger < Ougai::Logger
  def create_fields(severity, time, progname, msg, exc)
    fields = super
    ctx = OpenTelemetry::Trace.current_span.context
    if ctx.valid?
      fields[:trace_id]    = ctx.hex_trace_id
      fields[:span_id]     = ctx.hex_span_id
      fields[:trace_flags] = ctx.trace_flags.to_i
    end
    fields
  end
end

logger = OtelAwareLogger.new($stdout)
logger.info('payment processed', amount: 42.00, currency: 'USD')
```

### Semantic Logger

```ruby
# Gemfile: gem 'semantic_logger'
require 'semantic_logger'
require 'opentelemetry'

module OtelFormatter
  def self.call(log, logger)
    ctx = OpenTelemetry::Trace.current_span.context
    fields = {
      level:   log.level,
      time:    log.time.iso8601(3),
      message: log.message
    }
    if ctx.valid?
      fields[:trace_id]    = ctx.hex_trace_id
      fields[:span_id]     = ctx.hex_span_id
      fields[:trace_flags] = ctx.trace_flags.to_i
    end
    fields.merge!(log.payload) if log.payload
    fields.to_json + "\n"
  end
end

SemanticLogger.default_level = :info
SemanticLogger.add_appender(io: $stdout, formatter: OtelFormatter)

logger = SemanticLogger['MyService']
logger.info('user action', user_id: 123)
```

### Rails with `rails_semantic_logger`

```ruby
# Gemfile
# gem 'rails_semantic_logger'

# config/initializers/logging.rb
require 'opentelemetry'

module OtelFormatter
  def self.call(log, logger)
    ctx = OpenTelemetry::Trace.current_span.context
    fields = {
      level:      log.level,
      time:       log.time.iso8601(3),
      message:    log.message,
      controller: log.name
    }
    if ctx.valid?
      fields[:trace_id] = ctx.hex_trace_id
      fields[:span_id]  = ctx.hex_span_id
    end
    fields.merge!(log.payload) if log.payload
    fields.to_json + "\n"
  end
end

SemanticLogger.add_appender(io: $stdout, formatter: OtelFormatter)
```

## GOOD vs BAD

```ruby
# BAD — log without trace context; cannot correlate to a span
Rails.logger.info("order placed for user #{user_id}")
# Output: I, [2026-03-23] INFO -- : order placed for user 42
# No trace_id — cannot find the span this log came from in Tsuga

# GOOD — structured log with trace context injected
ctx = OpenTelemetry::Trace.current_span.context
logger.info('order placed', {
  user_id:  user_id,
  trace_id: ctx.hex_trace_id,
  span_id:  ctx.hex_span_id
})
# Output: {"level":"INFO","message":"order placed","user_id":42,"trace_id":"abc...","span_id":"def..."}
```

## Collector Configuration for Log Forwarding

After emitting JSON logs to stdout, configure the OTel Collector to collect them:

```yaml
# collector.yaml — filelog receiver reads stdout JSON
receivers:
  filelog:
    include: [/var/log/pods/**/my-service/*.log]
    operators:
      - type: json_parser
        timestamp:
          parse_from: attributes.time
          layout: '%Y-%m-%dT%H:%M:%S.%LZ'
      - type: move
        from: attributes.trace_id
        to: attributes.TraceId
      - type: move
        from: attributes.span_id
        to: attributes.SpanId
```

See `otel-collector` skill for complete pipeline configuration.

## Verification

```bash
# Confirm logs arrive with trace correlation
tsuga logs search --query "context.service.name:<your-service> trace_id:*" --max-results 3

# Verify a specific trace ID correlates across spans and logs
tsuga spans search --query "context.service.name:<your-service>" --max-results 1
# Note the traceId from output, then:
tsuga logs search --query "trace_id:<trace-id-from-above>" --max-results 5
```

If verification fails:
- `trace_id` absent from logs → verify your log formatter runs while a span is active; check `ctx.valid?` returns true
- Zero log results in Tsuga → `tsuga-debug-no-data` (likely a Collector filelog pipeline issue)
