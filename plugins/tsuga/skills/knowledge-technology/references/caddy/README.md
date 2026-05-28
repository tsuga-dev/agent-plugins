# Caddy Integration Context Bundle

## Technology Summary

| Field | Value |
|---|---|
| Technology | Caddy |
| Tech slug | caddy |
| Deployment model | self-hosted / cloud / k8s |
| Telemetry source | Caddy built-in Prometheus metrics (`/metrics`) |
| Primary version | Caddy v2 (v2.6+) |
| Persona focus | SRE |
| Primary use-case | reliability |
| Integration scope | core HTTP server + reverse proxy |

---

## What Caddy Is (Operational Context)

Caddy is a modern HTTP/2+HTTP/3 web server written in Go, known for automatic HTTPS via Let's Encrypt/ZeroSSL and a JSON/Caddyfile configuration model. In a typical SRE context, Caddy acts as a **TLS-terminating reverse proxy** or **static file server**, sitting in front of application backends. It is commonly deployed as a Kubernetes ingress controller (via `ingress-caddy`), in Docker Compose stacks, and on bare-metal edge nodes.

**What stub_status is to NGINX, the `/metrics` endpoint is to Caddy.** Caddy exposes rich Prometheus metrics natively since v2.5.0; no separate exporter is required. The metrics endpoint is served by the admin API (default: `localhost:2019/metrics`) or via a `metrics` handler in the HTTP server block.

**Important scoping note:** Caddy's stub-status equivalent (`caddy_http_requests_in_flight`) gives only global in-flight request counts. Per-route or per-upstream detailed breakdowns are labeled by `server` (virtual server name) and `handler` (middleware name like `file_server`, `reverse_proxy`). These labels become the primary dimension split in dashboards.

---

## Key Concepts

### Concept Map

```
Client
  │
  │ TCP/TLS
  ▼
[Caddy HTTP Server]
  │
  ├─ server: "srv0" (or named server)
  │   │
  │   ├─ route → handler: "file_server"
  │   │   └─ serves static files
  │   │
  │   └─ route → handler: "reverse_proxy"
  │       │
  │       ├─ upstream: "backend1:8080" (healthy/unhealthy)
  │       ├─ upstream: "backend2:8080"
  │       └─ load balancing policy
  │
  └─ metrics collection
      ├─ caddy_http_request_duration_seconds (histogram) → per server+handler+code+method
      ├─ caddy_http_requests_in_flight (gauge) → per server+handler
      ├─ caddy_reverse_proxy_upstreams_healthy (gauge) → per upstream
      └─ caddy_http_request_errors_total (counter) → per server+handler
```

**Key state transition for reverse_proxy:**
```
Request arrives → upstream selected (round-robin/lb) → upstream health checked
  → if healthy: proxy request → await response → return to client
  → if unhealthy: mark upstream down → failover to next upstream → passive/active health check recovery
```

### Histogram Metrics

Caddy exposes four histogram metrics (`caddy_http_request_duration_seconds`, `caddy_http_response_duration_seconds`, `caddy_http_request_size_bytes`, `caddy_http_response_size_bytes`). Each histogram is ingested via the OTel Prometheus receiver as three related time series:

| Suffix | Type | Meaning |
|--------|------|---------|
| `_count` | delta counter | Total number of observations (= request count) |
| `_sum` | delta counter | Sum of all values (= total duration/bytes) |
| `_bucket` | delta counter | Per-le-bound bucket counts (for percentile estimation) |

For request rate, use `caddy_http_request_duration_seconds_count` (delta → sum + per-second).
For percentile latency, use the base metric name (`caddy_http_request_duration_seconds`) with percentile aggregation if Tsuga supports it, or approximate from buckets.

### Labels → Context Fields

Caddy Prometheus labels map to Tsuga context attributes via OTel Prometheus receiver:

| Caddy label | Expected Tsuga field | Notes |
|-------------|---------------------|-------|
| `server` | `context.server` | Virtual server name (e.g., `srv0`, `https`) |
| `handler` | `context.handler` | Middleware handler name (e.g., `reverse_proxy`, `file_server`) |
| `code` | `context.code` | HTTP status code (e.g., `200`, `404`, `503`) |
| `method` | `context.method` | HTTP method (e.g., `GET`, `POST`) |
| `upstream` | `context.upstream` | Upstream address (e.g., `backend:8080`) |
| `statuscode` | `context.statuscode` | Admin API requests status code |
| `path` | `context.path` | Admin API request path |

All assumptions — must be verified in Stage 2.

### Automatic HTTPS

Caddy obtains and renews TLS certificates automatically. Cert-related metrics (ACME challenges, renewal errors) are not exposed in the Prometheus metrics endpoint — they appear only in structured logs. If TLS health is a concern, it must come from log parsing (Stage 4).

---

## Golden Signals

| Signal | Metric(s) | Healthy range | Concerning range |
|--------|-----------|---------------|-----------------|
| Request rate | `caddy_http_request_duration_seconds_count`/s | Stable baseline | >3× spike or zero during expected traffic |
| Error rate | `caddy_http_request_errors_total`/s | Near zero | Any sustained nonzero |
| P95 Latency | `caddy_http_request_duration_seconds` p95 | < 500ms | > 1s sustained |
| In-flight requests | `caddy_http_requests_in_flight` | < 50% capacity | > 80% sustained |
| Upstream health | `caddy_reverse_proxy_upstreams_healthy` | All upstreams = 1 | Any = 0 |

---

## Confirmed Tsuga Prefixes

**Status as of Stage 1 (2026-03-31): NOT YET CONFIRMED — no Caddy metrics found in Tsuga.**

| Prefix | Status | Notes |
|--------|--------|-------|
| `caddy_*` | INFERRED (not confirmed) | Caddy v2 native Prometheus metrics |
| `go_*` | INFERRED (not confirmed) | Go runtime metrics (same as nginx/haproxy exporters) |
| `process_*` | INFERRED (not confirmed) | Process-level metrics |
| `promhttp_*` | INFERRED (not confirmed) | Prometheus handler metrics |

Stage 2 must run `tsuga_search_metrics.py "caddy"` after Caddy metrics are ingested to confirm prefix format (underscore vs dot notation).

---

## Telemetry Sources

### Primary: Caddy Built-in `/metrics` Endpoint

Caddy v2 serves Prometheus metrics natively. Enable via:

**Caddyfile:**
```
{
  admin localhost:2019
  servers {
    metrics
  }
}
```

Or via a dedicated metrics handler:
```caddyfile
:2019 {
  metrics
}
```

**JSON config:**
```json
{
  "admin": {
    "listen": "localhost:2019"
  },
  "apps": {
    "http": {
      "servers": {
        "metrics_server": {
          "listen": [":2019"],
          "routes": [{"handle": [{"handler": "metrics"}]}]
        }
      }
    }
  }
}
```

Scrape endpoint: `http://localhost:2019/metrics` (default) or wherever the admin API or `metrics` handler is configured.

### OTel Prometheus Receiver Configuration

```yaml
receivers:
  prometheus:
    config:
      scrape_configs:
        - job_name: caddy
          static_configs:
            - targets: ['localhost:2019']
          metrics_path: /metrics
```

---

## Metric Namespace Summary

### `caddy_http_*` — HTTP Request Metrics (14+ metrics via histogram expansion)

The HTTP metrics track all requests passing through Caddy's HTTP handlers. Since these are labeled by `server`, `handler`, `code`, and `method`, they provide the richest operational data.

| Metric | Type | Description |
|--------|------|-------------|
| `caddy_http_requests_in_flight` | gauge | Currently active requests |
| `caddy_http_request_errors_total` | counter | Middleware errors (not HTTP 4xx/5xx — these are internal handler errors) |
| `caddy_http_request_duration_seconds` | histogram | Full round-trip request duration (includes TLS handshake if applicable) |
| `caddy_http_response_duration_seconds` | histogram | Time to first byte (TTFB) |
| `caddy_http_request_size_bytes` | histogram | Total incoming request size (headers + body) |
| `caddy_http_response_size_bytes` | histogram | Total outgoing response size (headers + body) |

### `caddy_reverse_proxy_*` — Upstream Health

| Metric | Type | Description |
|--------|------|-------------|
| `caddy_reverse_proxy_upstreams_healthy` | gauge | 1 = healthy, 0 = unhealthy, per upstream address |

### `caddy_admin_*` — Admin API Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `caddy_admin_http_requests_total` | counter | Requests to the Caddy admin API (`/config`, `/id`, etc.) |

### `caddy_*` — Build Info

| Metric | Type | Description |
|--------|------|-------------|
| `caddy_build_info` | gauge | Always 1; labels: goarch, goos, goversion, version |

### Go Runtime + Process Metrics

Standard Go runtime metrics: `go_goroutines`, `go_memstats_*`, `process_*`, `promhttp_*`.

---

## Caveats and Footguns (20+)

1. **`caddy_http_request_errors_total` is NOT HTTP 4xx/5xx errors.** It counts middleware panics and internal handler failures. HTTP status codes (4xx/5xx) are visible as the `code` label on `caddy_http_request_duration_seconds_count`, not via a dedicated error counter.

2. **The `handler` label can be misleading.** A single request may be processed by multiple handlers in sequence (auth, logging, reverse_proxy). Each handler records its own metrics. This means request counts can appear inflated if you don't filter to the final handler.

3. **Histogram latency vs wall-clock latency.** `caddy_http_request_duration_seconds` measures the full round-trip including backend processing time. `caddy_http_response_duration_seconds` measures time-to-first-byte only. For backend latency proxy, prefer response_duration over request_duration.

4. **`caddy_reverse_proxy_upstreams_healthy` missing if no reverse_proxy configured.** If Caddy is used only as a file server, this metric does not exist. Dashboard must gate on it.

5. **Server labels are auto-generated.** If servers are not named in config, Caddy auto-assigns names like `srv0`, `srv1`. Labels are not human-friendly without naming conventions.

6. **P99 latency from histogram buckets requires carefully chosen bucket boundaries.** Caddy uses default histogram buckets (0.005, 0.01, 0.025, ..., 10s). If most of your traffic is very fast (< 5ms), all requests fall in the lowest bucket and percentile approximation is coarse.

7. **Admin API metrics (`caddy_admin_http_requests_total`) do NOT reflect user traffic.** The admin API is used for config reloads, not HTTP serving. High admin request rates indicate config churn, not user load.

8. **`go_*` and `process_*` metrics reflect the Caddy process itself**, not any backend it proxies to. High Go heap memory means Caddy is using memory, not that backends are memory-heavy.

9. **Caddy can be configured to serve metrics only on the admin API port.** If firewall rules block the admin port but allow the HTTP server port, you can also serve metrics via a `metrics` handler on the HTTP server block — but this exposes internal metrics to users. Use a dedicated internal metrics port.

10. **In-flight requests gauge resets on restart.** After a graceful reload, in-flight transitions to near-zero briefly even under high traffic. This is expected and not an error condition.

11. **histogram `_sum` is not the same as latency under load.** At high throughput, the average (`_sum` / `_count`) per-second can decrease due to parallelism. Do not interpret decreasing average as improvement without also checking in-flight count.

12. **`code` label on `caddy_http_request_duration_seconds` requires a filter for 5xx tracking.** There is no dedicated 5xx counter. To get error rate, filter `code:5xx` or group by `code` and identify 5xx buckets.

13. **Caddy v2.5 vs v2.6+ metrics naming.** Metrics naming was stabilized in v2.6. Earlier versions may use different label names or metric names. Verify version in `caddy_build_info`.

14. **`caddy_http_requests_in_flight` is a snapshot, not a rate.** Do not apply per-second to it. Use `max` aggregation for peak detection.

15. **High `caddy_reverse_proxy_upstreams_healthy` sum ≠ all healthy.** If you have 10 upstreams and sum = 9, one is down. Always check sum vs expected count, not just whether sum > 0.

16. **Metric cardinality explosion from high-cardinality labels.** `method` has 9+ possible values (GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS, CONNECT, TRACE). `code` has ~50+ possible values. Grouping by both simultaneously creates high cardinality. Choose one or the other for group-by.

17. **Histogram count vs actual request count.** If a request passes through N handlers, `caddy_http_request_duration_seconds_count` records N observations. For "true" request count, filter to the specific handler that processes final responses (typically `reverse_proxy` or `file_server`).

18. **The `server` label is the server config name, not the IP/hostname.** A single Caddy instance may serve multiple virtual hosts under one logical `server`. Do not treat `server` as equivalent to a hostname or IP.

19. **No per-route or per-vhost breakdown natively.** Caddy does not label metrics by Caddyfile route or hostname by default. All routes on a server share the same `server` label. Per-host breakdown requires access log processing.

20. **Admin API port (2019) must be reachable for scraping.** If using Kubernetes, the admin port must be exposed as a container port and scraped via Pod IP, not the Service IP (admin port is typically not behind a Service).

21. **`caddy_build_info` is not a health signal.** It is always 1 when the process is running. Use it only to confirm Caddy version per instance.

22. **Cumulative vs delta temporality.** All histogram `_count` and `_sum` are cumulative Prometheus counters; OTel Prometheus receiver converts them to delta. Dashboard widgets must use `per-second` (not `rate`) for these metrics. Must be verified in Stage 2.

---

## Log Intelligence (Stage 4)

### Caddy Access Log Format

Caddy's default log output is **structured JSON** (unlike NGINX's CLF). This makes parsing significantly easier.

**Default JSON access log:**
```json
{
  "ts": 1711900800.123456,
  "logger": "http.log.access",
  "msg": "handled request",
  "request": {
    "remote_ip": "192.168.1.1",
    "remote_port": "54321",
    "proto": "HTTP/2.0",
    "method": "GET",
    "host": "example.com",
    "uri": "/api/health",
    "headers": {"User-Agent": ["kube-probe/1.27"]}
  },
  "duration": 0.001234,
  "size": 42,
  "status": 200,
  "resp_headers": {"Content-Type": ["application/json"]}
}
```

Key fields for log parsing:
- `ts` → timestamp (Unix float)
- `status` → HTTP status code
- `duration` → request duration in seconds
- `size` → response size in bytes
- `request.method`, `request.host`, `request.uri`

**Error log format:**
```json
{
  "ts": 1711900800.123456,
  "level": "error",
  "logger": "http.log.error",
  "msg": "dial tcp backend:8080: connection refused",
  "request": {"remote_ip": "...", "proto": "...", "method": "...", "host": "...", "uri": "..."}
}
```

### Candidate Log Query Filters

- Access logs: `service.name:caddy AND logger:http.log.access`
- Error logs: `service.name:caddy AND logger:http.log.error`
- Upstream errors: `service.name:caddy AND logger:http.log.error AND level:error`
- In Kubernetes: `k8s.container.name:caddy AND logger:http.log.access`

### Stage 4 Notes

- Caddy JSON logs are directly parseable without grok — use JSON path extraction
- `duration` field is in seconds (float) — multiply by 1000 for ms
- TLS errors and certificate renewal events appear in `logger:tls` logs
- Access logs must be explicitly enabled in Caddyfile: `log { output stdout }`

---

## Top 10 Sources

1. [Caddy v2 Metrics Docs](https://caddyserver.com/docs/metrics)
2. [Caddy Source: HTTP Metrics](https://github.com/caddyserver/caddy/blob/master/modules/caddyhttp/metrics.go)
3. [Caddy Source: Reverse Proxy Metrics](https://github.com/caddyserver/caddy/blob/master/modules/caddyhttp/reverseproxy/metrics.go)
4. [Caddy Prometheus Module](https://github.com/caddyserver/caddy/blob/master/modules/metrics/adminmetrics.go)
5. [Caddy Admin API Docs](https://caddyserver.com/docs/api)
6. [OTel Prometheus Receiver](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/prometheusreceiver)
7. [Caddy Caddyfile Reference: log directive](https://caddyserver.com/docs/caddyfile/directives/log)
8. [Caddy reverse_proxy health checks](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#health-checks)
9. [Prometheus Histogram best practices](https://prometheus.io/docs/practices/histograms/)
10. [Caddy releases / changelog](https://github.com/caddyserver/caddy/releases)
