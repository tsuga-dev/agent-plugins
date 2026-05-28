# Local Verification — Go

## Overview

Before pointing a Go service at a production collector, route spans to stdout to confirm instrumentation is correct. Go has no ambient SDK defaults — every exporter, processor, and provider must be wired explicitly. For CLI tools and short-lived binaries, `provider.Shutdown(ctx)` is mandatory or spans queued in the batch processor are silently dropped.

## Console Span Exporter

Use the `stdouttrace` package from the OTel SDK to print spans as formatted JSON.

```go
import (
    "context"
    "log"

    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/stdout/stdouttrace"
    "go.opentelemetry.io/otel/sdk/resource"
    sdktrace "go.opentelemetry.io/otel/sdk/trace"
    semconv "go.opentelemetry.io/otel/semconv/v1.27.0"
)

func initTracer() func(context.Context) error {
    exporter, err := stdouttrace.New(stdouttrace.WithPrettyPrint())
    if err != nil {
        log.Fatal(err)
    }

    // Simplified for local testing. Production: use resource.Merge(resource.Default(), ...)
    // to inherit telemetry.sdk.* attrs — see references/quickstart.md.
    res := resource.NewWithAttributes(
        semconv.SchemaURL,
        semconv.ServiceName("my-service"),
    )

    provider := sdktrace.NewTracerProvider(
        sdktrace.WithSyncer(exporter), // SimpleSpanProcessor equivalent
        sdktrace.WithResource(res),
    )

    otel.SetTracerProvider(provider)
    return provider.Shutdown
}
```

`WithPrettyPrint()` formats each span across multiple indented lines. Without it, each span is a single-line JSON object.

**Output format:** Each finished span is written as a standalone JSON object per line (NDJSON). The output
is NOT wrapped in a `{"resourceSpans": [...]}` OTLP envelope — each line is an individual span record.
Keys use Go struct field names (camelCase-compatible). Example of one span line:

```json
{"Name":"handle_request","SpanContext":{"TraceID":"...","SpanID":"..."},"Parent":{"TraceID":"...","SpanID":"...","Remote":false},"SpanKind":2,"StartTime":"...","EndTime":"...","Attributes":null,...}
```

If your test infrastructure expects `{"resourceSpans":[...]}` OTLP JSON format, use the in-memory
exporter (`tracetest.SpanRecorder`) for assertions instead — see `references/testing.md`.

## SimpleSpanProcessor vs BatchSpanProcessor

`WithSyncer(exporter)` is the Go SDK shorthand for wrapping an exporter in a `SimpleSpanProcessor`. `WithBatcher(exporter)` uses `BatchSpanProcessor`.

| | `WithSyncer` / `SimpleSpanProcessor` | `WithBatcher` / `BatchSpanProcessor` |
|---|---|---|
| Export timing | Synchronous, on `span.End()` | Async, background goroutine |
| Local testing | Preferred — spans appear immediately in stdout | Requires `Shutdown` to flush; may miss spans |
| Production | Not recommended — adds latency per span | Correct choice |

Use `WithSyncer` for local development and tests. Use `WithBatcher` in production deployments.

## Short-Lived Processes and CLI Tools

For commands that run and exit, the batch processor's background goroutine may not have flushed when `main` returns. Always call `provider.Shutdown(ctx)` before exiting.

```go
func main() {
    ctx := context.Background()

    shutdown := initTracer()
    defer func() {
        // Give Shutdown up to 5 seconds to flush remaining spans
        shutdownCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
        defer cancel()
        if err := shutdown(shutdownCtx); err != nil {
            log.Printf("tracer shutdown error: %v", err)
        }
    }()

    tracer := otel.Tracer("my-cli")
    ctx, span := tracer.Start(ctx, "cli.run")
    defer span.End()

    runCommand(ctx)
}
```

`defer` + a timeout context is the idiomatic Go pattern. If the process is killed (SIGKILL), no cleanup runs — use `SimpleSpanProcessor` with `WithSyncer` for CLI tools to guarantee each span is written synchronously on `End()`.

## OTEL_TRACES_EXPORTER=console Environment Variable

The Go OTel SDK does not natively resolve `OTEL_TRACES_EXPORTER=console` without additional setup. Configure the `stdouttrace` exporter explicitly in code for local verification. If your setup uses the OTLP bridge and a contrib configurator, `console` may be recognized — check the specific configurator package docs.

For straightforward local testing, explicit code configuration is more reliable than env-var-driven configuration in Go.

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

Point the Go OTLP exporter at it:

```go
import "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"

exporter, err := otlptracegrpc.New(ctx,
    otlptracegrpc.WithEndpoint("localhost:4317"),
    otlptracegrpc.WithInsecure(),
)
```

```bash
OTEL_SERVICE_NAME=my-service go run ./cmd/myservice
```
