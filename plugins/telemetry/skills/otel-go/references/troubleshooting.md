# Endpoint, Protocol, and Troubleshooting — Go

## OTLP Protocol Reference

| Protocol | Port | Path auto-appended by SDK? | Go package |
|---|---|---|---|
| OTLP/HTTP | 4318 | Yes (`/v1/traces`, `/v1/metrics`, `/v1/logs`) | `otlptracehttp` / `otlpmetrichttp` |
| OTLP/gRPC | 4317 | No | `otlptracegrpc` / `otlpmetricgrpc` |

**Default:** OTLP/HTTP on port 4318 is the current recommended default (see `references/quickstart.md`). gRPC (4317) is opt-in when required by infrastructure. gRPC uses `host:port` format — no `http://` or `https://` scheme prefix. HTTP exporters auto-append the signal path.

## Tsuga Endpoint Configuration

**gRPC (recommended):**

```go
import (
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "google.golang.org/grpc/credentials"
    "google.golang.org/grpc/metadata"
)

traceExporter, err := otlptracegrpc.New(ctx,
    otlptracegrpc.WithEndpoint("ingest.<region>.tsuga.cloud:443"),
    otlptracegrpc.WithTLSCredentials(credentials.NewClientTLSFromCert(nil, "")),
    otlptracegrpc.WithHeaders(map[string]string{
        "tsuga-ingestion-key": os.Getenv("TSUGA_INGESTION_KEY"),
    }),
)
```

**HTTP/protobuf:**

```go
import "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"

traceExporter, err := otlptracehttp.New(ctx,
    otlptracehttp.WithEndpoint("ingest.<region>.tsuga.cloud:443"),
    otlptracehttp.WithHeaders(map[string]string{
        "tsuga-ingestion-key": os.Getenv("TSUGA_INGESTION_KEY"),
    }),
    // SDK auto-appends /v1/traces — do not add it here
)
```

**Via environment variables:**

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://ingest.<region>.tsuga.cloud:443
OTEL_EXPORTER_OTLP_HEADERS=tsuga-ingestion-key=<your-key>
OTEL_EXPORTER_OTLP_PROTOCOL=grpc  # or http/protobuf
```

> **gRPC TLS note:** For port 443 with gRPC, use `credentials.NewClientTLSFromCert(nil, "")` for system CA-signed certs. Do NOT use `WithInsecure()` for Tsuga — that disables TLS.

## Common Issues

### No spans arriving at Tsuga

1. **`http://` prefix in gRPC endpoint:** `otlptracegrpc.WithEndpoint("http://localhost:4317")` is invalid — remove the scheme. Use `"localhost:4317"` with `WithInsecure()` for local, or `"host:443"` with TLS creds for Tsuga.
2. **`SetTracerProvider` not called:** Without `otel.SetTracerProvider(tp)`, `otel.Tracer()` returns a noop tracer.
3. **Context not threaded:** If `context.Background()` is used in handlers, spans have no parent and may appear as orphans.
4. **Exporter timeout:** Default gRPC export timeout is 10 seconds.
5. **Service name not set:** Without `OTEL_SERVICE_NAME`, spans arrive as `unknown_service`. > To determine the correct service name, see `references/resource-attributes.md` → **Resolve resource attribute values**. For high-latency connections, increase it with `otlptracegrpc.WithTimeout(30 * time.Second)`.

### Metrics not arriving

```go
// Missing: otel.SetMeterProvider(mp)
// Without this, meter.Int64Counter() creates a noop counter
```

Also check that `PeriodicReader` has a non-zero interval:

```go
sdkmetric.NewPeriodicReader(metricExporter,
    sdkmetric.WithInterval(30 * time.Second),
)
```

### Spans arrive but are orphaned (missing parent)

- Handler using `context.Background()` instead of `r.Context()`
- `otelhttp` middleware not registered before the handler
- Context dropped when passing to goroutine

### Build errors with multiple OTel versions

Go module graph may pull in multiple versions of `go.opentelemetry.io/otel`. Run:

```bash
go mod tidy
go mod graph | grep opentelemetry
```

If there are mismatches, pin all OTel modules to the same version in `go.mod`:

```
require (
    go.opentelemetry.io/otel v1.42.0
    go.opentelemetry.io/otel/sdk v1.42.0
    go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc v1.42.0
    // ...
)
```

## Shutdown / Flush

The Go SDK's `TracerProvider` buffers spans in a `BatchSpanProcessor`. Spans are lost if the process exits before flushing.

**Recommended shutdown pattern:**

```go
func setupOTel(ctx context.Context) (func(context.Context) error, error) {
    // ... setup ...
    tp := sdktrace.NewTracerProvider(...)
    mp := sdkmetric.NewMeterProvider(...)

    otel.SetTracerProvider(tp)
    otel.SetMeterProvider(mp)

    return func(ctx context.Context) error {
        return errors.Join(tp.Shutdown(ctx), mp.Shutdown(ctx))
    }, nil
}

func main() {
    ctx := context.Background()
    shutdown, err := setupOTel(ctx)
    if err != nil {
        log.Fatal(err)
    }

    // Graceful shutdown with timeout
    defer func() {
        shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
        defer cancel()
        if err := shutdown(shutdownCtx); err != nil {
            log.Printf("OTel shutdown error: %v", err)
        }
    }()

    // ... run server ...
}
```

**Signal handling for servers:**

```go
quit := make(chan os.Signal, 1)
signal.Notify(quit, os.Interrupt, syscall.SIGTERM)
<-quit

shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
defer cancel()

if err := shutdown(shutdownCtx); err != nil {
    log.Printf("OTel shutdown error: %v", err)
}
```

**Common shutdown mistakes:**

- `defer shutdown(ctx)` where `ctx` is already cancelled — use a fresh `context.Background()` with timeout
- Not waiting for server to drain connections before calling `tp.Shutdown()`
- Shutdown timeout too short for high-volume services — the exporter needs time to send the final batch

## Resilience: Collector Unavailable

> **Beta caveat:** Go OTel logs are currently in Beta (`go.opentelemetry.io/otel/sdk/log` v0.x). Trace and metric APIs are stable.

When the OTLP collector is unreachable, the Go SDK **does not panic or crash** the service. The `BatchSpanProcessor` retries with backoff; spans are dropped when the retry queue fills. The application continues running normally.

**Default behavior:** `otlptracegrpc.New()` returns an exporter that retries connection failures. Errors are logged to the OTel error handler (default: stderr), not returned to application code.

**Graceful startup without collector:**

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/sdk/trace"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
)

func setupTracing(ctx context.Context, endpoint string) (func(context.Context) error, error) {
    if endpoint == "" {
        // No collector — use a no-op TracerProvider (traces work, nothing exported)
        otel.SetTracerProvider(trace.NewTracerProvider())
        return func(ctx context.Context) error { return nil }, nil
    }

    exp, err := otlptracegrpc.New(ctx,
        otlptracegrpc.WithEndpoint(endpoint),
        otlptracegrpc.WithReconnectionPeriod(5*time.Second),
    )
    if err != nil {
        return nil, err
    }
    tp := trace.NewTracerProvider(trace.WithBatcher(exp))
    otel.SetTracerProvider(tp)
    return tp.Shutdown, nil
}
```

**Disable OTel entirely via env var:**
```bash
OTEL_SDK_DISABLED=true ./myservice
```

**Key point:** Never `log.Fatal` on exporter initialization failure — the service should still serve traffic. Log a warning instead and continue with a no-op provider.
