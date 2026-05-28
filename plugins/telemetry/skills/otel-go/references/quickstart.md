# Quick Start — Go OTel SDK

> **Last verified:** 2026-03-23 | SDK: `go.opentelemetry.io/otel` v1.42.0

> Run `go version` — Go 1.22+ required for v1.42.0. If below, use the highest OTel release whose `go.mod` `go` directive does not exceed your version.

This file covers full SDK initialization for all three signals (traces, metrics, logs). For framework-specific wiring see `references/frameworks.md`. For per-signal detail see `references/spans.md`, `references/metrics.md`, `references/logs.md`.

---

## Step 1 — Install dependencies

```bash
# Core SDK
go get go.opentelemetry.io/otel@v1.42.0
go get go.opentelemetry.io/otel/sdk@v1.42.0

# Trace exporter (HTTP/protobuf default — recommended)
go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp@v1.42.0

# Metric exporter
go get go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp@v1.42.0

# Log SDK + exporter (Beta — same caveat)
go get go.opentelemetry.io/otel/log@v0.10.0
go get go.opentelemetry.io/otel/sdk/log@v0.10.0
go get go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploghttp@v0.10.0

# Log bridge (slog) — Beta; test stability before production
go get go.opentelemetry.io/contrib/bridges/otelslog@v0.10.0

# Log bridge (zap) — Beta; test stability before production
# go get go.opentelemetry.io/contrib/bridges/otelzap@v0.10.0

# gRPC opt-in (port 4317 instead of 4318):
# go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc@v1.42.0
# go get go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc@v1.42.0
```

---

## Step 2 — SDK initialization

```go
package main

import (
    "context"
    "errors"

    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
    "go.opentelemetry.io/otel/propagation"
    sdklog "go.opentelemetry.io/otel/sdk/log"
    sdkmetric "go.opentelemetry.io/otel/sdk/metric"
    "go.opentelemetry.io/otel/sdk/resource"
    sdktrace "go.opentelemetry.io/otel/sdk/trace"
    semconv "go.opentelemetry.io/otel/semconv/v1.27.0"

    "go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploghttp"
    "go.opentelemetry.io/otel/log/global"
)

func setupOTel(ctx context.Context) (func(context.Context) error, error) {
    // resource.Default() includes: telemetry.sdk.*, service.name=unknown_service,
    // and env var detector (OTEL_SERVICE_NAME, OTEL_RESOURCE_ATTRIBUTES).
    // It does NOT include host or process attrs — add resource.WithHost()/resource.WithProcess() if needed.
    // Merge to add your service-specific attrs.
    res, err := resource.Merge(
        resource.Default(),
        resource.NewWithAttributes(
            semconv.SchemaURL,
            semconv.ServiceName("my-service"),
            semconv.ServiceVersion("1.0.0"),
            semconv.DeploymentEnvironmentName("production"),
        ),
    )
    if err != nil {
        return nil, err
    }

    // Traces
    // otlptracehttp.New(ctx) with no options reads OTEL_EXPORTER_OTLP_ENDPOINT automatically.
    traceExporter, err := otlptracehttp.New(ctx)
    if err != nil {
        return nil, err
    }
    tp := sdktrace.NewTracerProvider(
        sdktrace.WithBatcher(traceExporter),
        sdktrace.WithResource(res),
    )
    otel.SetTracerProvider(tp)
    // IMPORTANT: must set propagator — default is no-op, which breaks distributed traces
    otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
        propagation.TraceContext{},
        propagation.Baggage{},
    ))

    // Metrics
    metricExporter, err := otlpmetrichttp.New(ctx)
    if err != nil {
        return nil, err
    }
    mp := sdkmetric.NewMeterProvider(
        sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExporter)),
        sdkmetric.WithResource(res),
    )
    otel.SetMeterProvider(mp)

    // Logs (Beta — test stability before production)
    // This path uses direct OTLP log export. Alternative: filelog receiver → see references/logs.md
    logExporter, err := otlploghttp.New(ctx)
    if err != nil {
        return nil, err
    }
    lp := sdklog.NewLoggerProvider(
        sdklog.WithProcessor(sdklog.NewBatchProcessor(logExporter)),
        sdklog.WithResource(res),
    )
    global.SetLoggerProvider(lp)

    return func(ctx context.Context) error {
        return errors.Join(tp.Shutdown(ctx), mp.Shutdown(ctx), lp.Shutdown(ctx))
    }, nil
}

// In main():
// shutdown, err := setupOTel(ctx)
// if err != nil { log.Fatal(err) }
// defer shutdown(ctx)
```

**If you are not using direct OTLP log export** (filelog receiver path instead), omit the log exporter block and the `lp.Shutdown` from the join. See `references/logs.md` for the filelog alternative.

---

## Step 3 — Environment variables

```bash
# see references/resource-attributes.md to resolve the correct service name
OTEL_SERVICE_NAME=my-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318    # HTTP/protobuf (default)
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=production,service.version=1.0.0

# gRPC opt-in: OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
# (also switch to otlptracegrpc / otlpmetricgrpc / otlploggrpc packages)
```

> **OTEL_PROPAGATORS note:** If `otel.SetTextMapPropagator()` is never called in code, the SDK defaults to a no-op propagator. Distributed traces will not propagate across services. Always call it explicitly.

> **OTEL_SERVICE_NAME vs resource.NewWithAttributes:** `OTEL_SERVICE_NAME` set in environment overrides the programmatic value when using `resource.Default()`. Use env vars for deployment-time configuration; use code for defaults.

---

## Step 4 — Post-deploy verification

```bash
# Confirm traces arrived
tsuga spans search --query "context.service.name:my-service" --max-results 3

# Confirm metrics
tsuga metrics list --filter "service.name=my-service"

# Confirm logs with trace correlation
tsuga logs search --query "context.service.name:my-service trace_id:*" --max-results 3
```

- No data → `tsuga-debug-no-data`
- Traces missing across services → `tsuga-debug-missing-trace-propagation`
- Want full signal check → `tsuga-smoke-test`

---

## Protocol / Exporter Quick Reference

| Exporter package | Port | Protocol | Use |
|---|---|---|---|
| `otlptracehttp` | 4318 | HTTP/protobuf | Default — simplest setup |
| `otlptracegrpc` | 4317 | gRPC | When gRPC is required by infra |

> **Go has no agent.** `OTEL_TRACES_EXPORTER` env var does NOT auto-configure a provider. You must initialize `TracerProvider` and `MeterProvider` in code.
