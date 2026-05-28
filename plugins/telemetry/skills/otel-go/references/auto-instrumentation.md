# Auto-Instrumentation — Go

## Overview

Go does not support bytecode injection (like Java's agent), so "auto-instrumentation" in Go means using instrumentation wrappers provided by the OpenTelemetry ecosystem for popular libraries. These are opt-in, middleware-style integrations — they require adding library-specific packages and registering them in your application code.

The Go contrib repository (`go.opentelemetry.io/contrib`) provides maintained instrumentation packages for all major frameworks and libraries.

## Available Instrumentation Packages

```bash
# HTTP servers and clients
go get go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp@latest

# gRPC
go get go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc@latest

# chi router (community-maintained — not in official contrib)
go get github.com/riandyrn/otelchi@latest

# gin
go get go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin@latest

# gorilla/mux
go get go.opentelemetry.io/contrib/instrumentation/github.com/gorilla/mux/otelmux@latest

# database/sql (community-maintained — not in official contrib)
go get github.com/XSAM/otelsql@latest

# AWS SDK v2
go get go.opentelemetry.io/contrib/instrumentation/github.com/aws/aws-sdk-go-v2/otelaws@latest

# Kafka (sarama) — DEPRECATED: Shopify/sarama moved to IBM/sarama.
# The contrib otelsarama package is no longer maintained.
# For IBM/sarama instrumentation, see github.com/dnwe/otelsarama (community fork).
# go get github.com/dnwe/otelsarama@latest
```

## net/http — Standard Library HTTP

Wrap your handler with `otelhttp.NewHandler`:

```go
import (
    "net/http"
    "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

func main() {
    mux := http.NewServeMux()
    mux.HandleFunc("/users", usersHandler)
    mux.HandleFunc("/health", healthHandler)

    // Wrap the entire mux — creates spans for all routes
    handler := otelhttp.NewHandler(mux, "http.server",
        // Exclude health checks from tracing
        otelhttp.WithFilter(func(r *http.Request) bool {
            return r.URL.Path != "/health"
        }),
    )

    http.ListenAndServe(":8080", handler)
}

// For outgoing HTTP requests, wrap the client transport:
client := &http.Client{
    Transport: otelhttp.NewTransport(http.DefaultTransport),
}
```

## gRPC

```go
import (
    "google.golang.org/grpc"
    "go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc"
)

// Server
server := grpc.NewServer(
    grpc.StatsHandler(otelgrpc.NewServerHandler()),
)

// Client (grpc.Dial is deprecated — use grpc.NewClient)
conn, err := grpc.NewClient(
    addr,
    grpc.WithStatsHandler(otelgrpc.NewClientHandler()),
    grpc.WithTransportCredentials(insecure.NewCredentials()),
)
```

> **Note:** `otelgrpc.UnaryServerInterceptor()` and `otelgrpc.StreamServerInterceptor()` are deprecated in favor of `otelgrpc.NewServerHandler()` (stats handler approach) which handles both unary and streaming.

## database/sql

Uses `github.com/XSAM/otelsql` (community-maintained; there is no official contrib `otelsql` package).

```go
import (
    "database/sql"
    "github.com/XSAM/otelsql"
    semconv "go.opentelemetry.io/otel/semconv/v1.27.0"
    _ "github.com/lib/pq"
)

// Open a database connection with OTel instrumentation
db, err := otelsql.Open("postgres", dsn,
    otelsql.WithAttributes(semconv.DBSystemPostgreSQL),
)
if err != nil {
    log.Fatal(err)
}
defer db.Close()

// Register DB connection pool metrics
_, err = otelsql.RegisterDBStatsMetrics(db)
if err != nil {
    log.Fatal(err)
}
```

## AWS SDK v2

```go
import (
    "github.com/aws/aws-sdk-go-v2/config"
    "github.com/aws/aws-sdk-go-v2/service/s3"
    "go.opentelemetry.io/contrib/instrumentation/github.com/aws/aws-sdk-go-v2/otelaws"
)

cfg, err := config.LoadDefaultConfig(ctx)
otelaws.AppendMiddlewares(&cfg.APIOptions)

s3Client := s3.NewFromConfig(cfg)
// All S3 API calls now create spans automatically
```

## Log Bridge (Experimental)

The Go OTel log bridge is **pre-stable (v0.x)**. Suitable for instrumentation tasks; validate against your SDK version before relying on it in production. Structured loggers with manual trace context injection are also available as an alternative.

```go
// go.opentelemetry.io/contrib/bridges/otelslog — experimental
// Only use in non-production environments or if you accept breaking API changes
import (
    "go.opentelemetry.io/contrib/bridges/otelslog"
    "log/slog"
)

logger := slog.New(otelslog.NewHandler("my-service"))
// Spans and logs are linked automatically — but this is beta
```

For production, use the manual trace-log correlation pattern in the SKILL.md (slog custom handler or zap field helper).

## What Needs Manual Instrumentation

Go's auto-instrumentation packages cover the transport/framework layer. You still need manual spans for:

- Business logic (e.g., `order.validate`, `payment.process`)
- Background goroutines — context must be explicitly passed
- Custom protocols not covered by contrib packages
- Batch processing where per-item spans are meaningful

## Verifying Auto-Instrumentation Is Active

```bash
# Make a request to your service, then:
tsuga spans search --query "context.service.name:my-service" --max-results 5
# Look for spans named "GET /path", "grpc.server", "db.query" etc.
```
