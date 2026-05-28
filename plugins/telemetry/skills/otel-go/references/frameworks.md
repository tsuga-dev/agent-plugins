# Framework-Specific Recipes — Go

## net/http (Standard Library)

```go
import (
    "net/http"
    "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/attribute"
    "go.opentelemetry.io/otel/codes"
)

func main() {
    tracer := otel.Tracer("my-service")

    mux := http.NewServeMux()

    mux.HandleFunc("/users/{id}", func(w http.ResponseWriter, r *http.Request) {
        ctx := r.Context()  // already has parent span set by otelhttp middleware

        ctx, span := tracer.Start(ctx, "db.getUser")
        defer span.End()

        span.SetAttributes(attribute.String("user.id", r.PathValue("id")))

        user, err := getUserFromDB(ctx, r.PathValue("id"))
        if err != nil {
            span.RecordError(err)
            span.SetStatus(codes.Error, err.Error())
            http.Error(w, "not found", http.StatusNotFound)
            return
        }
        writeJSON(w, user)
    })

    // Wrap the mux with otelhttp middleware
    handler := otelhttp.NewHandler(mux, "http.server",
        otelhttp.WithFilter(func(r *http.Request) bool {
            // Exclude health probes from tracing
            return r.URL.Path != "/health" && r.URL.Path != "/ready"
        }),
        otelhttp.WithSpanNameFormatter(func(op string, r *http.Request) string {
            // Use method + path pattern for low-cardinality span names
            return r.Method + " " + r.URL.Path
        }),
    )

    http.ListenAndServe(":8080", handler)
}

// Outgoing HTTP client
func callDownstream(ctx context.Context, url string) (*http.Response, error) {
    client := &http.Client{
        Transport: otelhttp.NewTransport(http.DefaultTransport),
    }
    req, _ := http.NewRequestWithContext(ctx, "GET", url, nil)
    return client.Do(req)
}
```

## chi

```bash
go get github.com/riandyrn/otelchi@latest
```

```go
import (
    "github.com/go-chi/chi/v5"
    "github.com/go-chi/chi/v5/middleware"
    "github.com/riandyrn/otelchi"
)

func main() {
    r := chi.NewRouter()

    // Add otelchi middleware — creates spans for each request
    r.Use(otelchi.Middleware("my-service",
        otelchi.WithFilter(func(r *http.Request) bool {
            return r.URL.Path != "/health"
        }),
    ))
    r.Use(middleware.Logger)
    r.Use(middleware.Recoverer)

    r.Get("/users/{userID}", func(w http.ResponseWriter, r *http.Request) {
        ctx := r.Context()
        userID := chi.URLParam(r, "userID")

        ctx, span := otel.Tracer("my-service").Start(ctx, "db.getUser")
        defer span.End()
        span.SetAttributes(attribute.String("user.id", userID))

        user, err := getUserFromDB(ctx, userID)
        if err != nil {
            span.RecordError(err)
            span.SetStatus(codes.Error, err.Error())
            http.Error(w, err.Error(), http.StatusInternalServerError)
            return
        }
        writeJSON(w, user)
    })

    http.ListenAndServe(":8080", r)
}
```

## gin

```bash
go get go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin@latest
```

```go
import (
    "github.com/gin-gonic/gin"
    "go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/attribute"
    "go.opentelemetry.io/otel/codes"
    "go.opentelemetry.io/otel/trace"
)

func main() {
    r := gin.Default()

    // Add OTel middleware
    r.Use(otelgin.Middleware("my-service"))

    r.GET("/users/:id", func(c *gin.Context) {
        ctx := c.Request.Context()

        ctx, span := otel.Tracer("my-service").Start(ctx, "db.getUser")
        defer span.End()
        span.SetAttributes(attribute.String("user.id", c.Param("id")))

        user, err := getUserFromDB(ctx, c.Param("id"))
        if err != nil {
            span.RecordError(err)
            span.SetStatus(codes.Error, err.Error())
            c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
            return
        }
        c.JSON(http.StatusOK, user)
    })

    // Health check without OTel — add before middleware or use filter
    r.GET("/health", func(c *gin.Context) {
        c.Status(http.StatusOK)
    })

    r.Run(":8080")
}
```

## gRPC

```bash
go get go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc@latest
```

```go
import (
    "google.golang.org/grpc"
    "go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc"
)

// Server — use stats handler (preferred over interceptors)
func main() {
    lis, _ := net.Listen("tcp", ":50051")

    server := grpc.NewServer(
        grpc.StatsHandler(otelgrpc.NewServerHandler()),
    )

    pb.RegisterMyServiceServer(server, &myServiceImpl{})
    server.Serve(lis)
}

// Client (grpc.Dial is deprecated — use grpc.NewClient)
func newClient(addr string) (*grpc.ClientConn, error) {
    return grpc.NewClient(addr,
        grpc.WithStatsHandler(otelgrpc.NewClientHandler()),
        grpc.WithTransportCredentials(insecure.NewCredentials()),
    )
}

// Server method — ctx already has span set by otelgrpc stats handler
func (s *myServiceImpl) GetUser(ctx context.Context, req *pb.GetUserRequest) (*pb.User, error) {
    ctx, span := otel.Tracer("my-service").Start(ctx, "user.get")
    defer span.End()

    span.SetAttributes(attribute.String("user.id", req.UserId))

    user, err := s.db.GetUser(ctx, req.UserId)
    if err != nil {
        span.RecordError(err)
        span.SetStatus(codes.Error, err.Error())
        return nil, status.Error(codes.Internal, err.Error())
    }
    return user, nil
}
```

## Context Threading Pattern

In all Go frameworks, context must flow through every layer:

```go
// ALWAYS thread ctx — never use context.Background() in handlers
func handleRequest(ctx context.Context, req *Request) (*Response, error) {
    ctx, span := tracer.Start(ctx, "handle.request")
    defer span.End()

    // Pass ctx to all downstream calls
    result, err := callDatabase(ctx, req.ID)  // NOT callDatabase(context.Background(), req.ID)
    if err != nil {
        span.RecordError(err)
        span.SetStatus(codes.Error, err.Error())
        return nil, err
    }

    result2, err := callExternalService(ctx, result)
    if err != nil {
        span.RecordError(err)
        span.SetStatus(codes.Error, err.Error())
        return nil, err
    }

    return buildResponse(ctx, result2), nil
}

## Lifecycle Logging

Structured log events correlated with OTel trace context.

```go
package main

import (
    "context"
    "log/slog"
    "os"
    "go.opentelemetry.io/otel/trace"
)

// OTelHandler wraps slog to inject trace context
type OTelHandler struct{ slog.Handler }

func (h OTelHandler) Handle(ctx context.Context, r slog.Record) error {
    span := trace.SpanFromContext(ctx)
    if span.SpanContext().IsValid() {
        r.AddAttrs(
            slog.String("trace_id", span.SpanContext().TraceID().String()),
            slog.String("span_id", span.SpanContext().SpanID().String()),
        )
    }
    return h.Handler.Handle(ctx, r)
}

var logger = slog.New(OTelHandler{slog.NewJSONHandler(os.Stdout, nil)})

// --- Service startup ---
func logStartup(ctx context.Context) {
    logger.InfoContext(ctx, "service starting",
        "version", os.Getenv("APP_VERSION"),
        "environment", os.Getenv("DEPLOYMENT_ENV"),
        "otlp_endpoint", os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT"),
    )
}

// --- Request lifecycle (net/http middleware) ---
func loggingMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        logger.InfoContext(r.Context(), "request received",
            "method", r.Method,
            "path", r.URL.Path,
        )
        rw := &responseWriter{ResponseWriter: w}
        next.ServeHTTP(rw, r)
        logger.InfoContext(r.Context(), "request completed",
            "method", r.Method,
            "path", r.URL.Path,
            "status", rw.status,
        )
    })
}

// --- Graceful shutdown ---
func logShutdown(ctx context.Context, shutdown func(context.Context) error) {
    logger.InfoContext(ctx, "service shutting down")
    if err := shutdown(ctx); err != nil {
        logger.ErrorContext(ctx, "otel shutdown error", "error", err)
    }
    logger.InfoContext(ctx, "otel providers shut down")
}
```

> Go 1.21+ `log/slog` is the recommended structured logger. The `OTelHandler` wrapper injects `trace_id` and `span_id` from the active span context.

> **Beta:** `go.opentelemetry.io/otel/sdk/log` (Go OTel log bridge) is Beta — the pattern above uses `slog` directly with OTel context injection, which is the stable recommended approach.

## Microservices Propagation Pattern

Two-service HTTP call: caller injects trace context, callee extracts and creates a child span.

**Caller service (outbound HTTP):**

```go
import (
    "net/http"
    "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
    "go.opentelemetry.io/otel"
)

// Use otelhttp.NewTransport — injects W3C traceparent header automatically
client := &http.Client{Transport: otelhttp.NewTransport(http.DefaultTransport)}

func callDownstream(ctx context.Context, userID string) (*User, error) {
    tracer := otel.Tracer("caller-service")
    ctx, span := tracer.Start(ctx, "call.user-service")
    defer span.End()

    req, _ := http.NewRequestWithContext(ctx, "GET",
        "http://user-service/users/"+userID, nil)
    // W3C traceparent injected by otelhttp transport

    resp, err := client.Do(req)
    if err != nil {
        span.RecordError(err)
        return nil, err
    }
    defer resp.Body.Close()
    // ... decode response ...
    return user, nil
}
```

**Callee service (inbound HTTP):**

```go
import "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

// otelhttp.NewHandler extracts W3C headers and starts a child span
mux := http.NewServeMux()
mux.HandleFunc("/users/{id}", getUser)

handler := otelhttp.NewHandler(mux, "user-service")
http.ListenAndServe(":8080", handler)

func getUser(w http.ResponseWriter, r *http.Request) {
    // The span for this handler is automatically a child of the caller's span
    ctx := r.Context()
    tracer := otel.Tracer("user-service")
    _, span := tracer.Start(ctx, "db.get_user")
    defer span.End()
    // ...
}
```

**Manual inject/extract** (without otelhttp):

```go
import "go.opentelemetry.io/otel/propagation"

// Caller — inject
propagator := otel.GetTextMapPropagator()
propagator.Inject(ctx, propagation.HeaderCarrier(req.Header))

// Callee — extract
ctx = otel.GetTextMapPropagator().Extract(r.Context(), propagation.HeaderCarrier(r.Header))
ctx, span := tracer.Start(ctx, "handle.request")
defer span.End()
```

**Validate in Tsuga:** Query `tsuga spans search --service caller-service` and confirm parent_span_id on the callee's root span matches the caller's span ID.
```
