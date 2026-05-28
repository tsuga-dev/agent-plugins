# LiteSpeed Integration Context Bundle

## Metadata

**Technology:** LiteSpeed Web Server (LSWS / OpenLiteSpeed)
**Deployment:** self-hosted
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** mixed (Prometheus exporter via OTel Prometheus receiver; no native OTel receiver exists)
**Integration scope:** core service only
**Primary use-case:** reliability and performance

---

## How to use this bundle

- `01_litespeed_metrics.csv` — source of truth for all metric names, types, temporality, units, safe aggregations, and group-by fields. Use this for every widget query.
- `02_litespeed_dashboard_plan.yaml` — dashboard blueprint: sections, widgets, derived signals, explanation notes, triage chains, and playbooks.
- `03_litespeed_state.yaml` — machine-readable stage status, unknowns, and reconciliation state. Check the `unknowns` block before Stage 2.
- `04_litespeed_memory.md` — human-readable narrative: key decisions, assumptions, and what Stage 2 must verify first.
- Stage 2 will create `05_litespeed_metric_catalog.csv` as the discovered metric catalog for reconciliation memory and coverage checks.
- Stage 4 should read `## Log intelligence (Stage 4 handoff)` below and `03_litespeed_state.yaml` → `log_intel` before designing log routes.

---

## What it is and what "good" looks like

LiteSpeed Web Server is a high-performance, event-driven web server and reverse proxy. It is a drop-in Apache replacement (reads `.htaccess`, same config directives) that uses a non-blocking architecture with a small number of long-lived worker processes — no fork-per-request. OpenLiteSpeed (OLS) is the free open-source edition; LiteSpeed Enterprise (LSWS) is the commercial version with advanced features.

**Where it runs:** On-premises bare metal, VMs, or Kubernetes (via the LiteSpeed Ingress Controller). Commonly deployed in shared hosting control panels (cPanel, CyberPanel, CloudPanel) and high-traffic CMS stacks (WordPress + LSCache).

**What "good" looks like:**
- `litespeed_up` = 1 on all instances
- Connection utilization (HTTP + SSL) below 70% of configured maximums
- `litespeed_wait_queue_depth_per_app` = 0 for all LSAPI/FCGI worker pools — any non-zero value means PHP workers are exhausted and requests are queuing
- Public cache hit ratio above 80% for content-heavy vhosts (LSCache fully warmed)
- Backend app pool (`INUSE_CONN / EMAXCONN`) below 80% for LSAPI workers

**Paging intent (high-level):** Page when `litespeed_up` = 0, when connection pools are exhausted, or when LSAPI wait queue depth is non-zero for more than 60 seconds (active backend starvation).

**Top 3 incident shapes:**
1. **PHP worker exhaustion** — `litespeed_wait_queue_depth_per_app` > 0, `litespeed_connections_in_use_per_app` = pool max → start with Backend Workers section.
2. **Traffic surge / connection exhaustion** — `litespeed_available_connections` near 0, HTTP/SSL connection utilization > 90% → start with Connections & Saturation section.
3. **Cache bypass cascade** — cache hit ratio drops suddenly, request rate to backend spikes, LSAPI pool pressured → start with Cache Efficiency section, then Backend Workers.

**Confirmed by sources:** Architecture (event-driven, multi-worker), `.rtreport` format and field semantics, Prometheus exporter metric names — all from https://github.com/litespeedtech/litespeed-prometheus-exporter and https://docs.litespeedtech.com/lsws/realtime/.

**Best-practice inference:** Connection utilization thresholds (70%, 90%), cache hit ratio target (80%), LSAPI pool utilization target (80%) — reasonable for high-traffic web servers; not documented as specific thresholds by LiteSpeed.

---

## Key concepts

### Glossary

| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| `.rtreport` | Plain-text file at `/tmp/lshttpd/.rtreport` updated every ~10 s by LiteSpeed; source for all Prometheus metrics | All metrics derive from this file; no OTel native receiver | All |
| Worker process | LiteSpeed child process handling connections; one `.rtreport.N` file per CPU core/worker | Metrics across core files must be aggregated | All |
| MAXCONN | Configured maximum concurrent HTTP connections | Denominator for connection utilization; raised by tuning `maxConns` | Connections |
| MAXSSL_CONN | Configured maximum concurrent SSL/TLS connections | Separate limit from plain HTTP; can be exhausted independently | Connections |
| PLAINCONN | Currently active plain HTTP (non-SSL) connections | Real-time saturation indicator for HTTP traffic | Connections |
| SSLCONN | Currently active SSL/TLS connections (HTTP/1.1, HTTP/2, HTTP/3 all use SSL) | All encrypted traffic regardless of protocol version | Connections |
| AVAILCONN | Available plain HTTP connection slots (MAXCONN - active) | Capacity headroom; approaching 0 = saturation | Connections |
| AVAILSSL | Available SSL connection slots | Same semantics as AVAILCONN but for TLS | Connections |
| IDLECONN | Connections open but not processing a request | High idle count = keep-alive overhead; not a saturation signal | Connections |
| REQ_PROCESSING | In-flight requests currently being processed by the server (all vhosts or per-vhost) | Sustained high value = slow backends or saturation | Throughput |
| REQ_PER_SEC | Gauge — requests per second computed by LiteSpeed over the last ~10 s window; NOT a counter | Do not apply `rate()` — already a rate | Throughput |
| TOT_REQS | Cumulative total requests since process start — a true counter | Apply `rate()` for rate-of-change | Throughput |
| BPS_IN / BPS_OUT | Bytes per second inbound/outbound for plain HTTP; pre-computed gauge | Do not apply `rate()` | Throughput |
| SSL_BPS_IN / SSL_BPS_OUT | Bytes per second for SSL/TLS traffic; pre-computed gauge | Covers HTTP/2 and HTTP/3 traffic as well | Throughput |
| Virtual host (VHost) | Named website configuration within LiteSpeed; each appears as `REQ_RATE [VHostName]` | Per-vhost metrics allow isolating hot tenants | Throughput |
| LSCache | LiteSpeed's built-in full-page cache; stores rendered HTML responses | Reducing backend load is the primary mission; absence = all requests hit backend | Cache |
| Public cache | LSCache shared cache for unauthenticated / common responses | High hit rate dramatically reduces PHP worker load | Cache |
| Private cache | LSCache per-user cache for logged-in sessions | Relevant in CMS setups with authenticated users | Cache |
| Static hits | OS-level static file serving (JS, CSS, images, fonts) not going through LSCache dynamic cache | Should be a large % of total requests in content-heavy setups | Cache |
| EXTAPP | External application type served by LiteSpeed: LSAPI, FCGI, CGI, PROXY, AJP13, SERVLET | Each EXTAPP type has its own connection pool tracked by `app_type` label | Backend Workers |
| LSAPI | LiteSpeed's proprietary SAPI for PHP/Python/Ruby; faster than FPM; pool managed via `lsphp` | Most common backend type; `WAITQUE_DEPTH > 0` = PHP starvation | Backend Workers |
| FCGI | FastCGI-compatible external application | Used for non-LSAPI PHP or other CGI apps | Backend Workers |
| CMAXCONN | Configured maximum connections to an EXTAPP pool | Hard configuration ceiling | Backend Workers |
| EMAXCONN | Effective/pool maximum connections (may differ from CMAXCONN due to dynamic limits) | Denominator for pool utilization | Backend Workers |
| POOL_SIZE | Number of active worker processes/threads in the EXTAPP pool | Drops when workers crash | Backend Workers |
| INUSE_CONN | Currently in-use connections to an EXTAPP backend | Numerator for utilization; at EMAXCONN = fully saturated | Backend Workers |
| IDLE_CONN | Idle connections in the EXTAPP pool | At 0 with WAITQUE_DEPTH > 0 = all workers busy | Backend Workers |
| WAITQUE_DEPTH | Requests waiting for an available EXTAPP connection | Critical: any non-zero value means backend is saturated | Backend Workers |
| HTTP/3 + QUIC | UDP-based HTTP/3 — LiteSpeed developed lsquic and has broad HTTP/3 support | HTTP/3 traffic is counted under SSL metrics (no separate breakdown) | Throughput |

### Concept Map

```
Client -> TCP/UDP connect -> LiteSpeed Listener (HTTP or HTTPS/HTTP2/HTTP3)
LiteSpeed Listener -> increments PLAINCONN or SSLCONN
LiteSpeed Listener -> increments BPS_IN / SSL_BPS_IN (pre-computed gauge)

LiteSpeed VHost Router -> routes request to matching Virtual Host
VHost -> increments REQ_PROCESSING, REQ_PER_SEC per VHost

VHost -> checks LSCache (public/private)
LSCache hit -> increments PUB_CACHE_HITS_PER_SEC / PRIVATE_CACHE_HITS_PER_SEC -> response served
LSCache miss -> increments EXTAPP queue for LSAPI/FCGI/PROXY

VHost -> static file check
Static file -> increments STATIC_HITS_PER_SEC -> response served (no backend)

LiteSpeed -> dispatches to EXTAPP (LSAPI lsphp, FCGI, CGI, PROXY)
EXTAPP -> takes INUSE_CONN slot from EXTAPP pool
EXTAPP pool exhausted (INUSE_CONN = EMAXCONN) -> request enters WAITQUE_DEPTH
WAITQUE_DEPTH > 0 -> active backend starvation -> latency degrades -> connections accumulate

EXTAPP response -> LiteSpeed -> response to client
LiteSpeed -> increments BPS_OUT / SSL_BPS_OUT (pre-computed gauge)

LiteSpeed -> MAXCONN limit (plain) or MAXSSL_CONN limit (SSL)
PLAINCONN approaching MAXCONN -> AVAILCONN drops to 0 -> new connections refused
SSLCONN approaching MAXSSL_CONN -> AVAILSSL drops to 0 -> SSL connections refused

Multi-core LiteSpeed -> one .rtreport.N per worker
Prometheus exporter -> globs all .rtreport files -> aggregates into server-level metrics

LiteSpeed Kubernetes Ingress -> adds L4CONN, L4_BPS_IN, L4_BPS_OUT (passthrough mode)
L4 metrics -> only visible in K8s deployments; absent in standard setups

PHP worker crash -> POOL_SIZE drops -> EMAXCONN effectively lower -> faster saturation
PHP memory limit hit -> LSAPI worker restart -> POOL_SIZE blips -> brief saturation spike
```

### Entities and dimensions

| Entity | Tsuga field (INFERRED — verify Stage 2) | Why useful | Cardinality risk | Safe Top-N |
|---|---|---|---|---|
| Virtual host | `context.vhost` | Isolate hot tenants, per-site health | Low-medium (10-100 vhosts typical) | 20 |
| EXTAPP type | `context.app_type` | Compare LSAPI vs FCGI vs PROXY pools | Very low (6 fixed values) | 6 |
| EXTAPP name | `context.app_name` | Per-application-pool diagnostics | Low-medium (1 per VHost typically) | 20 |
| Worker core | `context.core` | Usually aggregated away; useful for imbalance debugging only | Low | Do NOT group-by in overview — aggregate to server level |
| Host / instance | `context.scope.name` | Multi-instance setups; isolate per-node | Low-medium | 20 |
| Environment | `context.env` | Stage, prod, dev separation | Very low | Always filter, not group-by |
| Team | `context.team` | Ownership boundaries | Low | Always filter, not group-by |
| K8s cluster | `context.k8s.cluster.name` | K8s deployments only | Low | 10 |
| K8s namespace | `context.k8s.namespace.name` | K8s deployments only | Medium | 20 |

**Do NOT group-by:** `context.core` in overview (always aggregate to server level); raw IP addresses from L4 metrics.

### Tsuga field mapping

| Prometheus label | Recommended context.* key | Must-exist vs optional | Notes |
|---|---|---|---|
| `vhost` | `context.vhost` | Optional (present only on per-vhost metrics) | Empty string = server aggregate row |
| `app_type` | `context.app_type` | Optional (present only on EXTAPP metrics) | CGI|LSAPI|FCGI|PROXY|AJP13|SERVLET |
| `app_name` | `context.app_name` | Optional (present only on EXTAPP metrics) | Application name e.g. `lsphp`, `wsgiApp` |
| `core` | `context.core` | Optional (worker core file suffix) | Usually aggregated away by exporters |
| — | `context.scope.name` | Must-exist (for instance-level filtering) | Hostname or k8s pod name |
| — | `context.env` | Must-exist | prod / staging |
| — | `context.team` | Must-exist | Owning team |
| — | `context.k8s.cluster.name` | Optional (K8s only) | |
| — | `context.k8s.namespace.name` | Optional (K8s only) | |

**Confirmed by sources:** Prometheus label names confirmed from exporter source (collector/metrics.go). Tsuga context.* key names are **INFERRED** — Stage 2 must verify actual attribute keys by inspecting discovered metric attributes.

**Best-practice inference:** Mapping `vhost` → `context.vhost`, `app_type` → `context.app_type` follows standard Tsuga Prometheus-receiver convention, but exact key names depend on how the OTel Prometheus receiver propagates labels. Verify in Stage 2.

---

## Golden signals

### Traffic (Throughput)

**What it means for LiteSpeed:** Request rate (`REQ_PER_SEC`) per virtual host, plus raw bandwidth (`BPS_IN/OUT`, `SSL_BPS_IN/OUT`). LiteSpeed pre-computes rate gauges internally — do NOT apply `rate()` to `_per_second` metrics.

**Typical causes when it degrades:** Upstream load balancer failure, DNS issue, bot flood dropping connection rate, or cache invalidation storm pushing all requests through to PHP backend.

**Best telemetry sources:** `litespeed_requests_per_second_per_vhost` (server-side request rate per VHost), `litespeed_incoming_http_bytes_per_second` + `litespeed_incoming_ssl_bytes_per_second` (total inbound bandwidth).

**What people page on:** Sustained drop in request rate with litespeed_up = 1 (silent rejection), or traffic spike causing connection exhaustion.

**Section questions:** Is total request rate within normal range? Which VHost is generating the most traffic? Is there a sudden bandwidth spike?

**Confirmed by sources:** Metric semantics from LiteSpeed `.rtreport` format documentation.

### Errors

**What it means for LiteSpeed:** LiteSpeed's `.rtreport` does NOT expose HTTP status code breakdowns — there are no 4xx/5xx error rate metrics from the Prometheus exporter. Error visibility requires access log parsing (`%>s` field). The only proxy for errors from metrics alone is the upstream impact: if backends are saturated (`WAITQUE_DEPTH > 0`) and connection utilization is near max, errors are likely occurring.

**Typical causes when it degrades:** PHP fatal errors exhausting workers, upstream 502/504s from slow backends, ModSecurity WAF blocks (no metric visibility).

**Best telemetry sources:** Access log (Stage 4) for HTTP status codes. Prometheus metrics give indirect signals only (connection exhaustion, queue depth).

**What people page on:** Absent from metrics; visible in logs. WAITQUE_DEPTH > 0 is the nearest metric proxy for 504 Gateway Timeout risk.

**Section questions:** Covered implicitly via connection saturation and backend worker signals.

**Best-practice inference:** The absence of error rate metrics from `.rtreport` is confirmed. Log-based error rates are best practice for LiteSpeed.

### Latency

**What it means for LiteSpeed:** NOT available from `.rtreport` metrics. LiteSpeed does not expose p50/p95/p99 latency in its stats file. Latency must be derived from access logs (`%D` microseconds or `%T` seconds field). The nearest metric proxy is `REQ_PROCESSING` (in-flight requests) — sustained high in-flight count indicates slow backend or high concurrency.

**Best telemetry sources:** Access log `%D` (microseconds) for real latency. `litespeed_current_requests_per_vhost` as a proxy for backend pressure.

**What people page on:** Covered indirectly: if WAITQUE_DEPTH > 0 and REQ_PROCESSING is elevated, p95 latency is likely degraded.

**Best-practice inference:** Latency gap confirmed from `.rtreport` docs — no latency field exists. This is a known gap; log-based SLO tracking is required.

### Saturation

**What it means for LiteSpeed:** Two saturation planes: (1) connection pool saturation (HTTP/SSL limits), (2) backend worker pool saturation (LSAPI/FCGI EMAXCONN + WAITQUE_DEPTH). WAITQUE_DEPTH > 0 is the most critical saturation signal — it means requests cannot get a PHP worker and are queuing in LiteSpeed memory.

**Typical causes when it degrades:** PHP memory leak requiring frequent worker restarts, slow database queries holding workers for a long time, bot floods bypassing cache.

**Best telemetry sources:** `litespeed_wait_queue_depth_per_app`, `litespeed_connections_in_use_per_app` / `litespeed_pool_max_connections_per_app`, `litespeed_available_connections`, `litespeed_available_ssl_connections`.

**What people page on:** WAITQUE_DEPTH > 0, AVAILCONN near 0, or AVAILSSL near 0.

**Section questions:** Are backend workers fully utilized? Is the wait queue non-zero? How close are HTTP and SSL connection pools to their limits?

**Confirmed by sources:** WAITQUE_DEPTH semantics confirmed from `.rtreport` docs and LiteSpeed community forums.

---

## Telemetry sources

| Source type | How collected | What it provides | Pros | Cons | Common pitfalls |
|---|---|---|---|---|---|
| **Official Prometheus exporter** (litespeedtech/litespeed-prometheus-exporter) | Systemd service reading `/tmp/lshttpd/.rtreport*`; scrape port 9936 `/metrics` | All `.rtreport` fields as Prometheus metrics | Official, maintained by LiteSpeed team; CGroups v2 support | GPL-3.0; does not expose HTTP status codes or latency | Multi-core files must all be read; exporter aggregates by default |
| **Hostinger Prometheus exporter** (hostinger/litespeed_exporter) | Same scrape model; reads glob pattern | Same metrics + optional per-host req rates + per-core split | MIT license; richer options | Less maintained than official | Same multi-core aggregation caveat |
| **OTel Prometheus receiver** | OTel collector scrapes Prometheus exporter endpoint | Bridges Prometheus → OTLP → Tsuga | Standard OTel pipeline; one configuration change | No native OTel receiver; Prometheus scrape interval adds latency | Metric names preserved as-is from Prometheus (no OTel semantic renaming) |
| **Netdata** | Plugin reads `.rtreport` files directly | Charts for requests, connections, cache, static | Zero install overhead | Not used for Tsuga ingestion; Netdata-only | |
| **WebAdmin REST endpoint** | `curl https://localhost:7080/status?rpt=detail` | Raw `.rtreport` content as text | Built-in, no extra process | Plain text, not Prometheus format; requires admin credentials | Not suitable for automated scraping at scale |
| **Access logs** | Log file at `/usr/local/lsws/logs/access.log`; configurable format | HTTP status codes, latency (`%D`), user agent, referer, cache status header | Only source for error rates and latency SLOs | Stage 4 (log route) needed; no metrics until parsed | `%D` = microseconds; `%T` = seconds; log format must include these |

**Confirmed by sources:** Exporter repos, LiteSpeed docs, Netdata GitHub. **Best-practice inference:** OTel Prometheus receiver as ingestion path is standard when no native OTel receiver exists.

**"No data" meaning:**
- Prometheus exporter: LiteSpeed is stopped, exporter is not running, or `.rtreport` file is missing (server not started)
- Per-vhost metrics absent: VHost never received traffic since server start
- EXTAPP metrics absent: No external application configured for that VHost (e.g., static-only site)
- Cache metrics at 0: LSCache not configured, VHost has no cacheable routes, or first-request cache warm-up not complete

**Optional features that change metrics:**
- CGroups metrics (`cgroups_*`): only emitted when LiteSpeed Containers add-on is active with cgroups v2 — absent in standard deployments
- L4 metrics: only in Kubernetes Ingress Controller mode
- `SESSIONS` field in EXTAPP: only in Kubernetes backend metrics

---

## Log intelligence (Stage 4 handoff)

### Confirmed by sources

**Log sources matrix:**

| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|---|---|---|---|---|
| Access log | `/usr/local/lsws/logs/access.log` or per-VHost configured path | Apache NCSA Combined (customizable) | Unstructured text; configurable to JSON | https://docs.openlitespeed.org/config/logs/ |
| Error log | `/usr/local/lsws/logs/error.log` | Fixed format: `[timestamp] [level] [message]` | Unstructured text | https://www.litespeedtech.com/docs/webserver/config/slog |
| VHost access log | Per-VHost configured path | Same as server-level (inherits or overrides format) | Same | LiteSpeed VHost config docs |
| ModSecurity audit log | `/usr/local/lsws/logs/modsec_audit.log` | ModSecurity AUDITLOG format (serial mode) | Unstructured multi-line | LSWS ModSecurity docs |

**Known log formats:**

**Access log (default NCSA Combined):**
```
127.0.0.1 - frank [10/Oct/2024:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 2326 "http://example.com/start.html" "Mozilla/5.0 ..."
```
Fields: `%h %l %u %t "%r" %>s %b "%{Referer}i" "%{User-Agent}i"`

**Access log (with latency and cache status — recommended config):**
```
127.0.0.1 - - [10/Oct/2024:13:55:36 -0700] "GET /page/ HTTP/2.0" 200 4820 "-" "Mozilla/5.0 ..." 1234 hit
```
Additional fields appended: `%D` (response time in microseconds), `%{X-LiteSpeed-Cache}o` (cache status)

**Error log:**
```
2024/10/10 13:55:36 [ERROR] [10523] [VHost:example.com] docRoot: /var/www/html/, [CGI] Child process [pid=10550] is not responding. Kill signal 9 sent.
```

### Best-practice inference

**Candidate query filters for Stage 4:**

| Filter | Rationale | Risk |
|---|---|---|
| `context.service.name:litespeed` | Precise; requires service.name set in collector config | May not be set in all deployments |
| `context.scope.name:lsws` OR `context.scope.name:openlitespeed` | Based on process name | Varies by deployment |
| Pattern match on log line: `"LiteSpeed"` OR `"litespeed"` in message | Broader; catches both access and error logs | May match other services with similar naming |
| Filename path: `/usr/local/lsws/logs/` | Log file path-based; works with file tailing collectors | Requires correct log path configured in collector |

**Attribute mapping hints:**

| Raw field | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| `%h` (client IP) | `context.http.client_ip` | Medium | Standard |
| `%>s` (status code) | `context.http.status_code` | High | Standard |
| `%r` (request line) | parsed into `context.http.method`, `context.http.url`, `context.http.protocol` | High | Grok split required |
| `%b` (response bytes) | `context.http.response_body_size` | High | |
| `%D` (microseconds) | `context.http.response_time_ms` (divide by 1000) | High | Present only if `%D` in log format |
| `%{Referer}i` | `context.http.referer` | High | |
| `%{User-Agent}i` | `context.http.user_agent` | High | Parse separately |
| `%{X-LiteSpeed-Cache}o` | `context.litespeed.cache_status` | High | Values: `hit`, `miss`, `stale`, `expired`, `no-cache` |
| `%v` (vhost) | `context.vhost` | High | Present only if in format |
| `%T` (seconds float) | `context.http.response_time_ms` (multiply by 1000) | High | Alternative to `%D` |

**Parsing risks:**
- **Variable log format**: LiteSpeed format is configurable per VHost; a single log route may not match all VHosts. Stage 4 should verify the actual format in use.
- **Quoted request line**: `"%r"` contains spaces; Grok `%{DATA:request}` inside quotes handles this, but escaped quotes inside the request line are rare edge cases.
- **Response bytes as `-`**: When no body is sent (304, HEAD), `%b` outputs `-` not `0`. Parser must handle this.
- **%D vs %T**: `%D` = microseconds (integer), `%T` = seconds (float). Confirm which is used before building the time conversion.
- **VHost-level log fragmentation**: Each VHost may write to its own log file; a unified route needs glob pattern on log path.
- **Multiline errors**: Error log entries for CGI/LSAPI crashes may span multiple lines; avoid naive newline splits.

---

## Caveats and footguns

- **[throughput-traffic]** `litespeed_requests_per_second_per_vhost` and all `_per_second` metrics are pre-computed GAUGES, not counters. **Never apply `rate()` or `per-second` post-function** — you will get a derivative of a rate, not a rate. (Source: LiteSpeed .rtreport docs)
- **[throughput-traffic]** `litespeed_total_requests_per_vhost` and all `TOTAL_*` metrics ARE cumulative counters. Apply `rate()` for rate-of-change. Do not chart raw cumulative values. (Source: Prometheus exporter source)
- **[connections-saturation]** HTTP connections and SSL connections are separate pools with separate maximums. You can exhaust SSL connections while HTTP connections are fine (and vice versa). Monitor both independently. (Source: .rtreport MAXCONN vs MAXSSL_CONN docs)
- **[connections-saturation]** `IDLECONN` (idle connections) are valid open TCP connections from keep-alive — NOT a problem signal. High IDLECONN with low REQ_PROCESSING is normal for keep-alive heavy traffic. (Inference)
- **[throughput-traffic]** HTTP/2 and HTTP/3/QUIC traffic is counted under SSL metrics (`SSLCONN`, `SSL_BPS_*`). There is no per-protocol breakdown. A "plain HTTP connection" jump may actually be a TLS rollback event. (Source: LiteSpeed architecture docs)
- **[backend-workers]** `WAITQUE_DEPTH` > 0 for even 1 request is a critical signal. There is no "acceptable" wait queue level — zero is the target. Any queuing means PHP workers are exhausted. (Source: LiteSpeed community forum; inference on threshold)
- **[backend-workers]** `POOL_SIZE` is the number of active EXTAPP processes, not the max. It can be lower than EMAXCONN if workers haven't been spawned yet (lazy init) or if workers have crashed. A sudden POOL_SIZE drop with high INUSE_CONN is a worker crash signal. (Source: .rtreport field semantics)
- **[backend-workers]** EXTAPP `app_type` values are fixed: CGI, LSAPI, FCGI, PROXY, AJP13, SERVLET. Do NOT group-by raw `app_name` values at high cardinality — use `app_type` as the primary group-by. (Source: exporter source)
- **[connections-saturation]** `litespeed_maximum_http_connections` and `litespeed_maximum_ssl_connections` are configuration values (gauges that rarely change). Do not apply rate functions. They are used as the denominator for utilization ratios only. (Source: .rtreport MAXCONN field)
- **[cache-efficiency]** LSCache cache hit metrics are 0 if LSCache is not configured for a VHost. Zero is normal for purely dynamic APIs or VHosts with no LSCache directives. Do not alert on zero without checking VHost cache config. (Inference)
- **[cache-efficiency]** Public and private cache are separate. A logged-in WordPress admin user bypasses public cache — private cache hits per second will be low even on a healthy site if few users are logged in. (Source: LiteSpeed LSCache docs)
- **[cache-efficiency]** Cache warm-up after restart: first ~5 minutes after LiteSpeed restart will show low cache hit ratios even on a healthy site. Do not alert on cache ratio during rolling restart windows. (Inference)
- **[backend-workers]** CGroups metrics (`cgroups_*`) are completely absent unless LiteSpeed Containers multi-tenant mode is active with cgroups v2. Do not expect these in a standard deployment. (Source: exporter README)
- **[throughput-traffic]** Per-vhost metrics require LiteSpeed to have received at least one request for that vhost since process start. A vhost with no traffic will have no metrics rows. (Source: .rtreport format semantics)
- **[connections-saturation]** Multi-core `.rtreport` files: LiteSpeed writes one `.rtreport.N` file per CPU core. The official exporter aggregates these. However, the `core` label may be present in some exporter configurations — do NOT group-by `context.core` in overview dashboards as it multiplies series counts. (Source: exporter README)
- **[backend-workers]** Kubernetes Ingress Controller L4 metrics (`litespeed_current_l4_connections`, `litespeed_incoming_l4_bytes_per_second`, `litespeed_outgoing_l4_bytes_per_second`) are only emitted in K8s LiteSpeed Ingress Controller mode. They will be absent in standard LSWS deployments. (Source: LiteSpeed K8s docs)
- **[cache-efficiency]** `TOTAL_PUB_CACHE_HITS` and `TOTAL_STATIC_HITS` are cumulative since server start, not windowed. For dashboards, use the `_per_second` gauges for rate signals, or apply `rate()` to cumulative counters for rate-of-change comparisons. (Source: .rtreport format)
- **[throughput-traffic]** BPS values are bytes per second, not bits. Multiply by 8 for megabits per second if needed for network team comparisons. (Source: LiteSpeed docs)
- **[backend-workers]** LSAPI PHP worker pool size can fluctuate during normal operation due to LiteSpeed's lazy spawn and idle reaping. Transient POOL_SIZE drops of 1-2 workers are not incidents unless paired with WAITQUE_DEPTH > 0. (Inference)
- **[throughput-traffic]** The aggregate `REQ_RATE []` (empty vhost) row in `.rtreport` gives the server total. Exporters typically emit this as vhost="" label. When summing per-vhost metrics, exclude the empty-vhost row to avoid double-counting. (Source: .rtreport format docs)

---

## Confirmed Tsuga prefixes

- `litespeed_` — **CONFIRMED** (32/33 planned metrics present in Tsuga; 1 missing: `litespeed_outgoing_bytes_per_second_per_vhost`; 3 unexpected exporter-internal metrics also present. Confirmed 2026-04-01 via `tsuga_build_metric_catalog.py`.)
- `cgroups_` — **CONFIRMED ABSENT** (0 metrics found; LiteSpeed Containers mode not active in this environment.)

**Confirmed attribute keys (Stage 2):** `context.vhost` (per-vhost metrics), `context.app_type` + `context.app_name` (per-EXTAPP metrics), `context.core`, `context.scope` (instance — NOT `context.scope.name`), `context.server.address`, `context.server.port`, `context.service.name`, `context.service.instance.id`, `context.url.scheme`.

---

## Discovery status

Discovery completed 2026-04-01 via `tsuga_build_metric_catalog.py`:
- 32 metrics found with `litespeed_` prefix (out of 33 planned; 1 missing)
- `cgroups_` prefix: 0 metrics (LiteSpeed Containers not active)
- 29/33 planned metrics confirmed; 4 missing (3 K8s-only expected; 1 unexpected: `litespeed_outgoing_bytes_per_second_per_vhost`)
- 3 unexpected metrics: `litespeed_exporter_scrapes_total`, `litespeed_exporter_scrape_failures_total`, `litespeed_version`
- Critical correction: context field is `context.scope` (not `context.scope.name`)
- Temporality corrections: 5 TOTAL_* / cache hit counters are delta in Tsuga (use `sum + per-second`, not `rate`)
- MAXCONN and MAXSSL_CONN are delta counter type in Tsuga despite being config constants

---

## Top sources

1. https://github.com/litespeedtech/litespeed-prometheus-exporter — Official Prometheus exporter; defines exact metric names, labels, and `.rtreport` field mappings. Primary source for all metric names.
2. https://docs.litespeedtech.com/lsws/realtime/ — LiteSpeed Real-Time Stats documentation; `.rtreport` format specification and field semantics.
3. https://github.com/hostinger/litespeed_exporter — Community exporter with MIT license; useful for cross-referencing metric names and per-host rate options.
4. https://docs.litespeedtech.com/cloud/kubernetes/metrics/ — Kubernetes Ingress Controller metrics documentation; source for L4 and SESSIONS metrics.
5. https://docs.openlitespeed.org/config/logs/ — OpenLiteSpeed log format documentation; confirms access log format variables and custom format options.
6. https://www.litespeedtech.com/docs/webserver/config/slog — LiteSpeed error log and server log configuration; confirms error log format.
7. https://www.litespeedtech.com/products/litespeed-web-server/features/feature-explanations — Architecture overview; confirms event-driven model, multi-worker design, HTTP/3 support.
8. https://github.com/litespeedtech/lsquic — QUIC/HTTP3 library by LiteSpeed; confirms HTTP/3 traffic flows through SSL connection counters.
9. https://www.litespeedtech.com/support/forum/threads/solved-understanding-rtreport-stats.5560/ — Community forum; confirms multi-core `.rtreport.N` file semantics and aggregation behavior.
10. https://www.litespeedtech.com/products/litespeed-web-server/editions — OLS vs LSWS comparison; confirms metric parity between editions.
