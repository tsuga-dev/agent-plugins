# Logs — Go OTel SDK

> **Last verified:** 2026-03-23 | bridges/otelslog v0.10.0, bridges/otelzap v0.10.0

This file covers log setup, trace-log correlation, and the two approaches: OTel log bridge (direct OTLP export) and filelog receiver (JSON stdout → Collector). For SDK initialization see `references/quickstart.md`.

---

## Log SDK Warning

> **The Go OTel log bridge (`go.opentelemetry.io/otel/log`) is Beta (v0.x).** Direct OTLP log export via `LoggerProvider` is pre-stable — test against your SDK version before relying on it in production. The **filelog receiver path** (Option B) is the stable ingestion alternative.

---

## Logger Choice Decision

| Use case | Recommendation |
|---|---|
| New Go 1.21+ service with no existing logging | `slog` (stdlib) — zero extra dependencies |
| Existing service already using zap | Keep `zap`, add `otelzap` bridge |
| Need maximum throughput, no reflection | `zap` |
| Greenfield service | `slog` |

---

## Option A — OTel Log Bridge (recommended approach for direct OTLP)

The bridge automatically injects `trace_id` and `span_id` into log records when you use `*Context` log variants. This eliminates the manual custom-handler approach.

### slog + otelslog bridge

```bash
go get go.opentelemetry.io/contrib/bridges/otelslog@v0.10.0
```

```go
import (
    "log/slog"

    "go.opentelemetry.io/contrib/bridges/otelslog"
)

// NewHandler uses the global LoggerProvider (set by setupOTel via global.SetLoggerProvider)
handler := otelslog.NewHandler("my-service")
slog.SetDefault(slog.New(handler))

// Always use *Context variants to get trace_id/span_id injection:
slog.InfoContext(ctx, "request handled",
    "http.request.method", "GET",
    "http.response.status_code", 200,
)
```

> **Key:** Use `slog.InfoContext(ctx, ...)`, not `slog.Info(...)`. The bridge reads `trace_id` and `span_id` from the context. Without ctx, no correlation fields are injected.

### zap + otelzap bridge

```bash
go get go.opentelemetry.io/contrib/bridges/otelzap@v0.10.0
```

```go
import (
    "context"
    "go.uber.org/zap"
    "go.opentelemetry.io/contrib/bridges/otelzap"
    "go.opentelemetry.io/otel/trace"
)

// otelzap.NewCore bridges zap → OTel LoggerProvider (routes logs through OTel pipeline)
core := otelzap.NewCore("my-service")
logger := zap.New(core)
defer logger.Sync()

// Unlike slog, zap has no built-in *Context logging variants.
// Build a per-request logger with trace fields at the handler boundary:
func withTraceFields(logger *zap.Logger, ctx context.Context) *zap.Logger {
    span := trace.SpanFromContext(ctx)
    if !span.SpanContext().IsValid() {
        return logger
    }
    sc := span.SpanContext()
    return logger.With(
        zap.String("trace_id", sc.TraceID().String()),
        zap.String("span_id", sc.SpanID().String()),
    )
}

// Usage — build once per request/operation:
requestLogger := withTraceFields(logger, ctx)
requestLogger.Info("request handled",
    zap.String("http.request.method", "GET"),
    zap.Int("http.response.status_code", 200),
)
```

> **otelzap vs otelslog:** `otelslog` has native `*Context` variants (`slog.InfoContext(ctx, ...)`) that automatically inject `trace_id`/`span_id`. With `otelzap`, you must explicitly build a context-enriched logger per operation. If trace correlation is the primary goal and you're starting fresh, prefer `otelslog`.

---

## Option B — Manual Correlation (no LoggerProvider required)

Use when you cannot use the log bridge (bridge instability, production constraints). Injects `trace_id`/`span_id` manually from context.

### slog — custom traceHandler

```go
import (
    "context"
    "log/slog"
    "os"

    "go.opentelemetry.io/otel/trace"
)

type traceHandler struct{ slog.Handler }

func (h traceHandler) Handle(ctx context.Context, r slog.Record) error {
    if span := trace.SpanFromContext(ctx); span.SpanContext().IsValid() {
        sc := span.SpanContext()
        r.AddAttrs(
            slog.String("trace_id", sc.TraceID().String()),
            slog.String("span_id", sc.SpanID().String()),
        )
    }
    return h.Handler.Handle(ctx, r)
}

logger := slog.New(traceHandler{slog.NewJSONHandler(os.Stdout, nil)})
slog.SetDefault(logger)

// Pass ctx to get correlation
slog.InfoContext(ctx, "msg", "key", "value")
```

### zap — field helper

```go
import (
    "context"
    "go.uber.org/zap"
    "go.opentelemetry.io/otel/trace"
)

func TraceFields(ctx context.Context) []zap.Field {
    if span := trace.SpanFromContext(ctx); span.SpanContext().IsValid() {
        sc := span.SpanContext()
        return []zap.Field{
            zap.String("trace_id", sc.TraceID().String()),
            zap.String("span_id", sc.SpanID().String()),
        }
    }
    return nil
}

// Usage
logger.Info("msg", TraceFields(ctx)...)
```

---

## Option C — filelog Receiver (Collector-based, no log SDK)

Use when you need the stable filelog ingestion path or prefer to decouple log export from the application SDK.

1. Configure your logger to emit JSON to stdout:

```go
// slog
logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
slog.SetDefault(logger)
```

2. Configure the OTel Collector `filelog` receiver to pick up stdout:

```yaml
receivers:
  filelog:
    include: [/var/log/pods/**/my-service/*.log]
    operators:
      - type: json_parser
exporters:
  otlp:
    endpoint: "${OTEL_EXPORTER_OTLP_ENDPOINT}"
service:
  pipelines:
    logs:
      receivers: [filelog]
      exporters: [otlp]
```

> Full filelog configuration → `otel-collector` skill.

---

## Go Goroutine Pitfall

```go
// BAD — goroutine loses trace context; trace_id not injected into logs
go func() {
    slog.InfoContext(context.Background(), "doing work")  // no trace_id
}()

// GOOD — capture ctx at launch
go func(ctx context.Context) {
    slog.InfoContext(ctx, "doing work")  // trace_id present if span in ctx
}(ctx)
```

---

## Verification

```bash
# Check logs are arriving with trace_id
tsuga logs search --query "context.service.name:<name> trace_id:*" --max-results 3
```

- `trace_id` absent → `tsuga-debug-missing-trace-propagation`
- Zero results → `tsuga-debug-no-data`
