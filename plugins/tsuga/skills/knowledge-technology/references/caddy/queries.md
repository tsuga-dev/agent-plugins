# Caddy

Go-based web server with auto-HTTPS. Healthy: in-flight bounded, low error rate, upstream pool healthy, Go runtime stable.

## Incident shapes

- **Upstream unhealthy** — `caddy_reverse_proxy_upstreams_healthy` drops → health-check failures
- **Error spike** — `caddy_http_request_errors_total` rises → backend or config
- **Latency regression** — request duration p95 climbs → upstream slow or handler regression
- **In-flight saturation** — `caddy_http_requests_in_flight` near process limit
- **Go runtime issues** — `go_goroutines` unbounded or `heap_alloc` growing = leak or deadlock

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `caddy_reverse_proxy_upstreams_healthy` | 0/1 | Per-upstream health |
| `caddy_http_request_duration_seconds` | s | Request latency histogram |
| `caddy_http_response_duration_seconds` | s | Response-write latency |
| `caddy_http_request_errors_total` | count | Error count by status |
| `caddy_http_request_duration_seconds_count` | count | Request count |
| `caddy_http_requests_in_flight` | count | Concurrent requests |
| `caddy_http_request_size_bytes` / `response_size_bytes` | bytes | Size histograms |
| `caddy_admin_http_requests_total` | count | Admin API usage (external spike = investigate) |
| `go_goroutines` | count | Growth = leak |
| `go_memstats_heap_alloc_bytes` / `heap_sys_bytes` | bytes | Heap posture |
| `process_resident_memory_bytes` | bytes | Process RSS |
| `process_cpu_seconds_total` | cpu-s | Per-second = CPU usage |

## Derived signals

- `Δerrors_total / Δrequest_count` — error rate.
- Histogram quantile on `request_duration_seconds` — p95/p99.
- Fraction of `upstreams_healthy == 1` — upstream health ratio.
- `go_goroutines` trend — healthy baseline 10-200; unbounded growth = leak.

## Log patterns

Caddy logs JSON by default:

- `"msg":"proxy error"` — reverse-proxy upstream error
- `"msg":"certificate_obtain_failed"` — ACME failure
- `"msg":"dial_backend"` with repeated `connection refused` — backend dial failures
- `"msg":"reading response from upstream"` — upstream closed early
- `"msg":"requesting certificate"` — ACME issue
- Request entries with `"status":5xx` — per-request failures

## Gotchas

- ACME auto-cert issuance can fail silently for one domain while others succeed. `certificate_obtain_failed` is the primary signal.
- Admin API (`:2019`) should not be public. Spike in `caddy_admin_http_requests_total` from external IP = security signal.
- In-flight requests include websockets; long-lived connections inflate `requests_in_flight` benignly.
- Goroutine count rises with HTTP/2 streams and websockets; high count ≠ leak. Look for monotonic growth over 30+ min.
- JSON log field names mix camelCase and snake_case. Filter on `msg`.
