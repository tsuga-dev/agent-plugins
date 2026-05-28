# NGINX Integration Context Bundle

## Metadata

**Technology:** NGINX (nginx-prometheus-exporter)
**Deployment:** self-hosted
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** mixed (Prometheus exporter scrape via OTel or Prometheus receiver)
**Integration scope:** core service only
**Primary use-case:** reliability and performance

---

## How to use this bundle

- `01_nginx_metrics.csv` — metric source of truth: types, temporality, safe aggregations, group-bys
- `02_nginx_dashboard_plan.yaml` — dashboard blueprint: sections, widgets, derived signals, explanation notes, triage chains, playbooks
- `03_nginx_state.yaml` — machine-readable stage status, unknowns, reconciliation state
- `04_nginx_memory.md` — human-readable decisions and handoff narrative
- Stage 2 will create `05_nginx_metric_catalog.csv` as the discovered metric catalog for reconciliation and coverage checks
- Stage 4 should read "Log intelligence (Stage 4 handoff)" and `03.log_intel` before creating log routes

---

## What it is and what "good" looks like

NGINX is a high-performance HTTP server, reverse proxy, and load balancer widely used as a Kubernetes ingress controller, API gateway, and static file server. It runs as a multi-worker process model: a master process manages a configurable number of worker processes, each capable of handling thousands of concurrent connections using an async event loop.

**What "good" looks like:**
- `nginx_up = 1` on all instances; any instance reporting 0 is unreachable or misconfigured
- Connection drop rate near 0%: accepted ≈ handled; persistent gap indicates resource exhaustion or misconfiguration
- Active connections stable and well below configured `worker_connections` limit
- Waiting (idle keep-alive) connections dominant in the active pool during normal operation
- Reading/writing connections low relative to active — spikes indicate slow clients or backends

**Incident shapes and first sections to check:**
1. **Traffic spike / overload**: `nginx_connections_active` climbs, `nginx_connections_waiting` drops, `nginx_connections_writing` spikes → check "Connection Pool" section
2. **Connection drops**: `nginx_connections_accepted` diverges from `nginx_connections_handled` → check "Health & Availability" and Connection Drop Rate QV
3. **NGINX down**: `nginx_up = 0` → check "Health & Availability" first; then "Exporter Health" to rule out scrape failure

### Confirmed by sources

NGINX stub_status provides exactly 8 operational metrics (confirmed in nginx docs). The `nginx_up` flag indicates scrape reachability, not whether NGINX is healthy inside. Connection `handled` ≤ `accepted` always; the gap is dropped connections.

Source: https://nginx.org/en/docs/http/ngx_http_stub_status_module.html

### Best-practice inference

`worker_connections` limit (default 1024 per worker) combined with `worker_processes` gives maximum concurrent connections. NGINX does not export its own configuration limits through stub_status, so saturation must be inferred from absolute connection counts relative to expected baseline.

---

## Key concepts

### Glossary

| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| stub_status | NGINX built-in status page providing global connection stats | Must be enabled in config; exposes the 7 operational counters and gauges | All sections |
| Worker process | OS process spawned by NGINX master to handle connections | Each worker runs async; saturation shows as reading+writing spike | connection-pool |
| Worker connections | Per-worker connection limit (`worker_connections` directive) | Max concurrent connections = workers × worker_connections | connection-pool |
| Keep-alive (waiting) | HTTP/1.1 persistent connections held open between requests | Waiting connections are healthy and expected; high waiting = efficient reuse | connection-pool |
| Reading | Connections where NGINX is reading the HTTP request header from the client | Sustained high reading = slow clients or header parsing pressure | connection-pool |
| Writing | Connections where NGINX is writing the HTTP response back to the client | Sustained high writing = slow backends or large responses | connection-pool |
| Accepted | Cumulative count of client connections accepted by NGINX | Monotonically increasing; per-second rate = inbound connection rate | traffic-throughput |
| Handled | Cumulative count of connections handled (no resource drop) | Should equal accepted; gap = dropped connections | health-availability |
| Active | Current active client connections (reading + writing + waiting) | Primary concurrency metric; does not include connections in accept queue | connection-pool |
| nginx_up | Gauge = 1 if last scrape succeeded, 0 if NGINX unreachable | Zero means NGINX is down OR exporter cannot reach stub_status | health-availability |
| nginx-prometheus-exporter | Open-source exporter by NGINX Inc. that scrapes stub_status | Version 1.4.2 confirmed; exposes `nginx_*` Prometheus metrics | exporter-health |
| stub_status endpoint | `/nginx_status` (or configured path) HTTP endpoint | Must be accessible by the exporter; firewall/auth misconfigs cause nginx_up=0 | health-availability |
| Event-driven model | NGINX uses epoll/kqueue per worker for non-blocking I/O | Allows thousands of concurrent connections per worker without threads | connection-pool |
| upstream | Backend server NGINX proxies to | Not exposed by stub_status; per-upstream metrics require NGINX Plus | traffic-throughput |
| vhost | Virtual host configured in NGINX | Not exposed by stub_status; per-vhost metrics require OTel module or log analysis | traffic-throughput |
| request | HTTP request counted by nginx_http_requests_total | Global count; no per-URL or per-vhost breakdown in stub_status | traffic-throughput |
| connection drop | Accepted − Handled > 0 | Indicates resource exhaustion (file descriptors, memory, worker_connections limit) | health-availability |
| scrape interval | How often the exporter polls nginx_status | Default varies; affects counter resolution | exporter-health |
| process_resident_memory_bytes | RSS memory of the nginx-prometheus-exporter process | Should be stable and small (~15–25 MB); spikes suggest exporter leak | exporter-health |
| go_goroutines | Go runtime goroutine count in the exporter | Should be stable; runaway goroutines = exporter memory leak | exporter-health |
| promhttp_metric_handler_requests_total | Count of HTTP scrapes by status code | code=200 = success; code=500/503 = scrape failure | exporter-health |

### Concept Map

```
Client -> sends TCP SYN -> NGINX kernel accept queue
NGINX kernel accept queue -> connection accepted -> nginx_connections_accepted increments
nginx_connections_accepted -> connection_handled IF resources available -> nginx_connections_handled increments
nginx_connections_accepted -> connection DROPPED IF resource limit hit -> gap = accepted - handled
Connection handled -> enters reading state -> nginx_connections_reading
Reading state -> header parsed -> transitions to writing state -> nginx_connections_writing
Writing state -> response sent -> transitions to waiting (keep-alive) OR closes -> nginx_connections_waiting
nginx_connections_waiting -> idle keep-alive pool -> new request arrives -> back to reading state
All active states -> nginx_connections_active = reading + writing + waiting (confirmed)
Each HTTP request completed -> nginx_http_requests_total increments
nginx_up -> reflects whether exporter can reach stub_status endpoint -> 0 = NGINX down OR network/config issue
nginx-prometheus-exporter -> scrapes /nginx_status -> exposes nginx_* metrics
nginx-prometheus-exporter -> also exposes go_* and process_* metrics -> own runtime health
promhttp_metric_handler_requests_total -> counts scrape attempts by HTTP status -> scrape reliability signal
Worker processes -> each handles subset of connections -> stub_status aggregates across ALL workers
NGINX master -> spawns worker_processes workers -> each limited by worker_connections directive
worker_connections limit -> when hit -> new connections queued or dropped -> accepted - handled gap
context.env -> filters dashboard to prod/staging -> all metrics
context.team -> filters to owning team -> all metrics
context.scope.name -> filters to individual NGINX instance -> all nginx_* metrics (verify in Stage 2)
```

### Entities and dimensions

| Entity | Why useful | Cardinality risk | Safe top-N | Group-by recommendation |
|---|---|---|---|---|
| NGINX instance (`context.scope.name`) | Per-pod/server breakdown for multi-instance deployments | Low–medium (10–100 pods typical) | 20 | Primary group-by for all nginx metrics |
| K8s namespace (`context.k8s.namespace.name`) | Namespace-level aggregation | Low (5–20 namespaces) | 10 | Secondary group-by for k8s deployments |
| K8s cluster (`context.k8s.cluster.name`) | Cross-cluster comparison | Very low (1–5 clusters) | 5 | Optional third level |
| Scrape status code (`context.code`) | For promhttp metric: distinguish 200 vs 500 vs 503 | Very low (3 values) | 3 | Only for promhttp_metric_handler_requests_total |
| Environment (`context.env`) | Prod vs staging comparison | Very low | 3 | Dashboard-level filter |
| Team (`context.team`) | Ownership filtering | Low | 10 | Dashboard-level filter |

**Do NOT group-by:**
- URL path or request method — not available in stub_status
- Upstream name — not available in stub_status
- Response code — not available in stub_status (requires NGINX Plus or access logs)

### Tsuga field mapping

**Confirmed by sources (OTel Prometheus receiver conventions):**

| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| (instance-level, e.g. pod name or hostname) | `context.scope.name` | Must-exist (instance identifier) |
| Kubernetes cluster | `context.k8s.cluster.name` | Optional (k8s deployments) |
| Kubernetes namespace | `context.k8s.namespace.name` | Optional (k8s deployments) |
| Environment (prod/staging) | `context.env` | Must-exist |
| Team ownership | `context.team` | Must-exist |
| HTTP status code label (promhttp only) | `context.code` | Optional (exporter-health section) |

**Best-practice inference:**
These field names follow standard OTel Prometheus receiver resource attribute mapping conventions. Actual field names in Tsuga must be verified in Stage 2. The `context.scope.name` field typically maps to the target's job/instance label in Prometheus.

---

## Golden signals

### Traffic

**What it means for NGINX:** Inbound HTTP request rate (`nginx_http_requests_total/s`) and inbound connection rate (`nginx_connections_accepted/s`). These are the primary load signals.

**Typical causes when degraded:** Client traffic spike, bot traffic, DDoS, deployment rollout bringing new traffic.

**Best telemetry:** `nginx_http_requests_total` (per-second), `nginx_connections_accepted` (per-second).

**What people page on:** Request rate drops to zero or spikes 5× baseline within a 5-minute window.

**Dashboard questions (1-3 per signal):**
- "Is the request rate normal?"
- "Is the connection accept rate changing?"

### Confirmed by sources: nginx_http_requests_total documented at https://nginx.org/en/docs/http/ngx_http_stub_status_module.html

### Errors

**What it means for NGINX:** Connection drops (accepted − handled > 0) indicate NGINX is rejecting connections due to resource limits. The stub_status exporter does not expose HTTP error codes.

**Typical causes when degraded:** `worker_connections` exhausted, file descriptor limit hit, insufficient memory, misconfigured OS network stack.

**Best telemetry:** Connection Drop Rate derived signal (formula: `(accepted − handled) / accepted × 100`).

**What people page on:** Connection drops > 0 sustained for > 1 minute.

### Best-practice inference: HTTP 4xx/5xx breakdown requires NGINX Plus or access log processing.

### Latency

**What it means for NGINX:** stub_status does not expose latency directly. Proxy latency can be inferred from the reading/writing connection state distribution (time in reading = slow clients; time in writing = slow backends/large responses).

**Best telemetry (proxy signal only):** Writing connections rising while request rate is stable suggests backend latency. Reading connections rising suggests slow client uploads.

**What people page on:** Not directly pageable from stub_status. Latency SLOs require access logs or NGINX Plus.

### Best-practice inference.

### Saturation

**What it means for NGINX:** Connection pool saturation. Active connections approaching `worker_processes × worker_connections` indicates risk of drops.

**Best telemetry:** `nginx_connections_active` (max), connection state breakdown (reading/writing/waiting).

**What people page on:** Active connections climbing while waiting connections drop to near zero — indicates worker pool saturation, new connections will be queued or dropped.

---

## Telemetry sources

| Source type | How collected | What it provides | Pros/cons | Common pitfalls |
|---|---|---|---|---|
| nginx-prometheus-exporter (v1.4.2) | Scrapes `/nginx_status` (stub_status) | 7 global nginx metrics + nginx_up | Simple; well maintained; NGINX Inc. official | Global only; no per-vhost, no HTTP status codes |
| OTel Prometheus receiver | Scrapes nginx-prometheus-exporter `/metrics` | All nginx_* + go_* + process_* metrics | Integrates with OTel pipeline | Adds process/go metrics that are exporter-level, not NGINX-level |
| NGINX Plus API | Native JSON API | Per-upstream, per-server, per-location, HTTP status codes, latency, bytes | Rich; official | Commercial only |
| NGINX OTel module | In-process OTel instrumentation | Request-level spans, latency by route | Request-level visibility | Requires recompilation or official build with module |
| Access logs | NGINX access log pipeline | Full HTTP request detail: status codes, latency, bytes, URL, client IP | Most complete | Requires log parsing; covered by Stage 4 |

### Confirmed by sources

nginx-prometheus-exporter v1.4.2 confirmed from user-provided metrics output (`nginx_exporter_build_info{version="1.4.2"}`).

### Best-practice inference

For production observability, stub_status should be complemented by access log processing (Stage 4) to get HTTP status code breakdown and per-endpoint latency.

---

## Log intelligence (Stage 4 handoff)

### Confirmed by sources

**Log sources matrix:**

| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|---|---|---|---|---|
| NGINX access log | `/var/log/nginx/access.log` (configurable) | Combined log format (CLF) or custom | Unstructured (text) | https://nginx.org/en/docs/http/ngx_http_log_module.html |
| NGINX error log | `/var/log/nginx/error.log` (configurable) | Multiline text: timestamp level PID tid message | Unstructured (text) | https://nginx.org/en/docs/ngx_core_module.html#error_log |
| Kubernetes pod logs | `kubectl logs` / log collector | Container stdout (usually access log piped there) | Unstructured | Standard k8s pattern |

**Known log formats:**

1. **Combined access log (default)**
   ```
   127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326 "http://www.example.com/start.html" "Mozilla/4.08 [en] (Win98; I ;Nav)"
   ```
   Fields: remote_addr, ident, auth_user, time_local (bracketed), request, status, body_bytes_sent, http_referer (quoted), http_user_agent (quoted)

2. **Error log**
   ```
   2024/10/01 12:00:00 [error] 1234#1234: *1 connect() failed (111: Connection refused) while connecting to upstream, client: 10.0.0.1, server: example.com, request: "GET / HTTP/1.1", upstream: "http://10.0.0.2:8080/", host: "example.com"
   ```
   Fields: timestamp, level (bracketed), pid#tid, connection_id, message, client, server, request, upstream, host

**Candidate query filters for Stage 4:**

1. **Precise**: `service.name:nginx` AND `log.source:access_log` — targets confirmed NGINX access logs; risk: service.name field name may differ
2. **Broader fallback**: text contains `"GET "` OR `"POST "` AND context.scope.name matches nginx pattern — risk: too broad, may match other HTTP services

**Attribute mapping hints:**

| Raw field | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| `remote_addr` | `http.client.ip` | Medium | Standard OTel HTTP attribute |
| `time_local` | `timestamp` | High | Parse as UTC |
| `request` (verb + path + proto) | `http.method` + `http.target` + `http.flavor` | Medium | Requires splitting |
| `status` | `http.status_code` | High | Integer |
| `body_bytes_sent` | `http.response_content_length` | Medium | Bytes |
| `http_referer` | `http.request.header.referer` | Low | Often "-" |
| `http_user_agent` | `http.user_agent` | High | Standard OTel |
| upstream | `nginx.upstream.addr` | Medium | NGINX-specific |
| host | `http.host` | High | Standard OTel |

**Parsing risks:**
- Quoted fields with spaces: `"GET /path HTTP/1.1"` — grok must account for quoted strings
- User-Agent contains spaces and special chars — use greedy match at end
- Error log is multiline — upstream context in error logs wraps across lines
- Custom log formats: many operators override `log_format` — the combined format is default but not universal
- Timezone in access log: `time_local` uses configured timezone; parse as local or configure NGINX to use UTC
- The `-` (dash) placeholder for missing values in CLF must be handled as null

### Best-practice inference

K8s deployments typically redirect NGINX logs to stdout/stderr, making them available via container log collectors (Fluent Bit, Vector). The Stage 4 query filter should target the container log stream.

---

## Caveats and footguns

- **[health-availability]** `nginx_up = 0` can mean NGINX is down OR the exporter cannot reach the stub_status endpoint (e.g., wrong URL configured, auth required). Always check exporter logs before declaring NGINX down. (Source: https://github.com/nginxinc/nginx-prometheus-exporter)

- **[health-availability]** Connection drop detection (`accepted - handled`) only works if both metrics are from the same scrape window and same instance. Cross-instance sums of accepted vs handled can mislead if instances restart at different times. (Inference)

- **[traffic-throughput]** `nginx_http_requests_total` counts requests, not connections. A single keep-alive connection handles multiple requests. The requests/s rate is always >= connections/s rate. Do not compare them as equivalent units. (Source: nginx stub_status docs)

- **[traffic-throughput, connection-pool]** There is no per-vhost, per-upstream, or per-URL breakdown in stub_status. All metrics are server-global. This is a fundamental limitation of the free NGINX tier. (Confirmed)

- **[connection-pool]** `nginx_connections_active` = reading + writing + waiting. It is NOT the number of workers or open file descriptors. Do not compare it directly to `worker_connections` limit without knowing `worker_processes`. (Source: nginx docs)

- **[connection-pool]** High `nginx_connections_waiting` is NORMAL under HTTP/1.1 keep-alive. It indicates efficient connection reuse, not idle waste. Only become concerned if waiting exceeds a sensible multiple of expected concurrent users. (Source: NGINX blog)

- **[connection-pool]** `nginx_connections_reading` is typically very low (0–5) under normal operation. A sustained nonzero value during low traffic indicates slow clients uploading large request bodies. (Inference)

- **[connection-pool]** The 3 connection state metrics (reading, writing, waiting) sum to `active`. Building derived ratios requires using `active` as denominator, not their sum, because both express the same total. (Confirmed)

- **[health-availability, traffic-throughput]** Both `nginx_connections_accepted` and `nginx_http_requests_total` are cumulative counters from the nginx-prometheus-exporter's perspective. The prometheus exporter exposes them as `counter` type. Their temporality in Tsuga (delta vs cumulative) must be confirmed in Stage 2 — always use the correct post-function. (Confirmed: prometheus counters are cumulative; OTel prometheus receiver converts to delta)

- **[traffic-throughput]** After an NGINX reload or restart, all cumulative counters reset to zero. This causes a dip to near-zero followed by a spike in rate metrics. This is expected; do not alert on a single dip without correlating with NGINX restart events. (Source: NGINX docs on reload)

- **[exporter-health]** The `go_*` and `process_*` metrics reflect the nginx-prometheus-exporter's own runtime, NOT NGINX's runtime. NGINX is a C program; it does not expose Go goroutines. Confusion between exporter health and NGINX health is a common mistake. (Confirmed)

- **[exporter-health]** `process_resident_memory_bytes` for the exporter should be approximately 15–25 MB under normal conditions. Values consistently above 100 MB may indicate a goroutine/memory leak in the exporter. (Inference from typical nginx-prometheus-exporter behavior)

- **[health-availability]** `nginx_up` is 0 or 1; it is not a counter. Do not apply `per-second` to it. (Confirmed)

- **[exporter-health]** `promhttp_metric_handler_requests_total` has a `code` label (200, 500, 503). In Tsuga, this attribute may appear as `context.code` or `context.http.status_code` — must be verified in Stage 2 before building filter-based signals. (Inference)

- **[connection-pool]** NGINX worker connection limit (`worker_connections`, default 1024) is a per-worker limit. With `worker_processes auto` (which sets workers = CPU cores), the total capacity is `worker_connections × CPU cores`. The exporter does not expose this configuration. (Source: NGINX docs)

- **[traffic-throughput]** Request rate and connection rate diverge as keep-alive usage increases. A healthy high-traffic NGINX instance will show request rate 5–20× connection rate. Unusually low ratio (close to 1:1) may indicate keep-alive is disabled or clients are closing after each request. (Inference)

- **[health-availability]** The nginx-prometheus-exporter uses Go HTTP client to scrape `/nginx_status`. If NGINX is behind a TLS certificate the exporter doesn't trust, scrapes fail silently (nginx_up=0). (Source: exporter documentation)

- **[exporter-health]** `go_goroutines` for the nginx-prometheus-exporter should be ~10–20 at steady state. The user-provided metrics show 15 goroutines, which is normal. (Confirmed from user-provided metrics)

- **[health-availability, connection-pool]** NGINX does not expose its own `worker_processes` count or `worker_connections` limit through stub_status. Saturation analysis must use absolute connection counts rather than utilization percentages. (Confirmed)

- **[traffic-throughput]** nginx_connections_accepted and nginx_connections_handled counts reset on NGINX restart. Cumulative totals across restarts are not meaningful; always use rate-based views. (Inference)

- **[connection-pool]** A ratio of writing connections much higher than reading connections indicates the bottleneck is on the response path (backend latency, large responses), not on the request ingestion path. (Source: NGINX performance tuning docs)

---

## Confirmed Tsuga prefixes

- `nginx_*` — **INFERRED** (nginx-prometheus-exporter v1.4.2 exposes 8 nginx_* metrics; user-provided metrics confirm names; Tsuga ingestion via OTel Prometheus receiver likely preserves underscore naming)
- `go_*` — **INFERRED** (standard Go runtime metrics from nginx-prometheus-exporter; all go_* metrics confirmed present in user-provided output)
- `process_*` — **INFERRED** (standard process metrics from nginx-prometheus-exporter; process_* metrics confirmed in user-provided output)
- `promhttp_*` — **INFERRED** (Prometheus HTTP handler metrics from nginx-prometheus-exporter; promhttp_metric_handler_requests_total confirmed in user-provided output)

Stage 2 discovery will confirm actual prefix structure in Tsuga and resolve exact metric names (underscore vs dot notation).

---

## Discovery status

Discovery: not yet performed (deferred to Stage 2). User provided raw Prometheus /metrics output confirming all metric names and types. Tsuga-specific names, attributes, and temporality must be confirmed via Stage 2 API discovery.

---

## Top sources

1. https://nginx.org/en/docs/http/ngx_http_stub_status_module.html — Official stub_status module documentation (metric definitions, enabled/disabled behavior)
2. https://github.com/nginxinc/nginx-prometheus-exporter — nginx-prometheus-exporter source, documentation, metric list, Docker image
3. https://nginx.org/en/docs/ngx_core_module.html — Core NGINX directives including worker_processes, worker_connections
4. https://nginx.org/en/docs/http/ngx_http_log_module.html — NGINX access log format documentation (Stage 4)
5. https://www.nginx.com/blog/inside-nginx-how-we-designed-for-performance-scale/ — NGINX event-driven architecture (worker model, connection states)
6. https://docs.nginx.com/nginx/admin-guide/monitoring/live-activity-monitoring/ — NGINX Plus monitoring (context for what stub_status does NOT expose)
7. https://opentelemetry.io/docs/collector/configuration/#receivers — OTel Prometheus receiver (how nginx_* metrics are ingested into OTel pipelines)
8. https://nginx.org/en/docs/http/ngx_http_upstream_module.html — Upstream module (confirms no per-upstream metrics in free tier)
9. https://github.com/nginxinc/nginx-prometheus-exporter/blob/main/README.md — nginx-prometheus-exporter README: installation, configuration, metric list
10. https://pkg.go.dev/github.com/prometheus/client_golang/prometheus/promhttp — promhttp handler metrics documentation (promhttp_metric_handler_requests_total semantics)
