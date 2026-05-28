# Distributed Context Propagation — Go

## Overview

Trace context must be explicitly propagated across service boundaries. The W3C TraceContext headers (`traceparent`, `tracestate`) carry the trace ID and span ID between services. Go has no ambient context — `context.Context` must be explicitly threaded through every function call and every goroutine.

## Inbound: Server Context Extraction

When using `otelhttp.NewHandler` or `otelgin`/`otelchi` middleware, inbound context extraction is automatic — the middleware reads `traceparent` from incoming HTTP headers.

**Manual extraction (custom transport):**

```go
import (
    "context"
    "net/http"

    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/propagation"
)

func myHandler(w http.ResponseWriter, r *http.Request) {
    // Extract trace context from incoming request headers
    ctx := otel.GetTextMapPropagator().Extract(r.Context(), propagation.HeaderCarrier(r.Header))

    // Start span as child of extracted context
    ctx, span := tracer.Start(ctx, "handle.request")
    defer span.End()

    // Pass ctx to all child operations
    doWork(ctx)
}
```

**gRPC server (manual extraction):**

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/propagation"
    "google.golang.org/grpc/metadata"
)

func (s *server) MyRPC(ctx context.Context, req *pb.Request) (*pb.Response, error) {
    // Extract from gRPC metadata
    md, _ := metadata.FromIncomingContext(ctx)
    carrier := make(propagation.MapCarrier)
    for k, vs := range md {
        if len(vs) > 0 {
            carrier[k] = vs[0]
        }
    }
    ctx = otel.GetTextMapPropagator().Extract(ctx, carrier)

    ctx, span := tracer.Start(ctx, "grpc.server.myRPC")
    defer span.End()

    return s.doWork(ctx, req)
}
```

## Outbound: Client Context Injection

**net/http — automatic with `otelhttp.NewTransport`:**

```go
import (
    "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

client := &http.Client{
    Transport: otelhttp.NewTransport(http.DefaultTransport),
}

req, _ := http.NewRequestWithContext(ctx, "GET", url, nil)
resp, err := client.Do(req)  // traceparent injected automatically
```

**Manual injection:**

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/propagation"
)

req, _ := http.NewRequestWithContext(ctx, "GET", downstreamURL, nil)

// Inject current context into request headers
otel.GetTextMapPropagator().Inject(ctx, propagation.HeaderCarrier(req.Header))

resp, err := http.DefaultClient.Do(req)
```

**gRPC client:**

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/propagation"
    "google.golang.org/grpc/metadata"
)

// Create outgoing metadata carrier
// Note: metadata.MD is map[string][]string, but propagation.MapCarrier is map[string]string.
// Copy propagation headers into metadata manually.
carrier := make(propagation.MapCarrier)
otel.GetTextMapPropagator().Inject(ctx, carrier)

md := metadata.New(nil)
for k, v := range carrier {
    md.Set(k, v)
}

// Attach to context for the gRPC call
outCtx := metadata.NewOutgoingContext(ctx, md)
resp, err := grpcClient.MyRPC(outCtx, req)
```

## Message Queue Propagation

For Kafka, SQS, and RabbitMQ Go patterns — including full semconv attributes, span naming, and the producer/consumer Link model — see **`references/async-messaging.md`**.

Key rule (summarized here for quick reference): consumer spans MUST use `trace.WithLinks(...)` — NOT parent-child — to avoid merging separate workflows into one trace.

## Goroutine Context Threading

Go context does not propagate automatically to goroutines. Always capture and pass `ctx` explicitly:

```go
// WRONG — goroutine uses context.Background(), trace context lost
go func() {
    doWork(context.Background())
}()

// CORRECT — capture parent ctx at launch time
go func(ctx context.Context) {
    ctx, span := tracer.Start(ctx, "background.work")
    defer span.End()
    doWork(ctx)
}(ctx)
```

## Anti-Pattern: Do Not Merge Separate Workflows

Queue consumers should not create child spans of the producer's trace. Use links instead:

```go
// WRONG — merges consumer into producer's trace
ctx, span := tracer.Start(extractedCtx, "consume.message")

// CORRECT — new root trace with link to producer
ctx, span := tracer.Start(context.Background(), "consume.message",
    trace.WithLinks(trace.Link{
        SpanContext: trace.SpanContextFromContext(extractedCtx),
    }),
)
defer span.End()
```

## gRPC Endpoint Protocol Note

When using gRPC for OTel export, do not prefix the endpoint with `http://`. The gRPC client resolves `host:port` directly:

```go
// WRONG — gRPC does not use http:// scheme
otlptracegrpc.WithEndpoint("http://localhost:4317")

// CORRECT
otlptracegrpc.WithEndpoint("localhost:4317")
otlptracegrpc.WithInsecure()  // for local dev only
```

## Preferred Pattern: autoprop (env-driven propagator)

Instead of hardcoding a propagator in code, use `autoprop` — it reads `OTEL_PROPAGATORS` at runtime and constructs a `TextMapPropagator` accordingly. This lets you change propagators without redeploying.

```bash
go get go.opentelemetry.io/contrib/propagators/autoprop
```

```go
import "go.opentelemetry.io/contrib/propagators/autoprop"

// In setupOTel() — replaces the manual TraceContext + Baggage setup:
otel.SetTextMapPropagator(autoprop.NewTextMapPropagator())
```

Then control the propagator via env var (no code change needed):

```bash
# Default — W3C TraceContext + Baggage
OTEL_PROPAGATORS=tracecontext,baggage

# B3 support (for Zipkin interop or legacy Istio)
OTEL_PROPAGATORS=tracecontext,baggage,b3
```

If `OTEL_PROPAGATORS` is not set, `autoprop` defaults to `tracecontext,baggage` — matching the OTel spec default.

## W3C TraceContext vs B3

Use W3C TraceContext (`traceparent`/`tracestate`) by default — it is the OTel standard and all modern services and collectors support it. Use B3 (`X-B3-TraceId`, `X-B3-SpanId`, `X-B3-Sampled`) only when interoperating with Zipkin-instrumented services, legacy Istio, or old Spring Cloud Sleuth. To accept both, configure a `CompositePropagator` with `TraceContext{}` and `b3.New()` from `go.opentelemetry.io/contrib/propagators/b3`.

## Tsuga Trace Continuity Validation

```bash
tsuga spans search --query "context.service.name:<caller-service>" --max-results 5
# Note traceId values
tsuga spans search --query "context.service.name:<callee-service> traceId:<trace-id>"
# parentSpanId on callee spans must match spanId from caller
```
