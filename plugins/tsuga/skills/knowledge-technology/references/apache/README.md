# Apache HTTP Server Integration Context Bundle

## Metadata

**Technology:** Apache HTTP Server  
**Tech Slug:** apache-http-server  
**Deployment:** self-hosted  
**Environment:** prod  
**Persona:** SRE, Dev, Ops  
**Telemetry:** mixed (OTel apache receiver + mod_status)  
**Scope:** core service only  
**Use-case:** reliability and performance  
**Where it runs:** Kubernetes (also on-prem bare metal / VM)  
**Cloud provider:** N/A  
**Tsuga context fields:** context.team, context.env  
**Bundle created:** 2026-04-01  
**Stage:** 1 (bundle creation complete; Stage 2 discovery pending)

---

## How to use this bundle

1. **Stage 1 (this bundle):** Reference files 00–04 to understand the technology, confirm metric names, and plan the dashboard.
2. **Stage 2 (discovery):** Run metric discovery against a live Apache instance (or OTel Collector scrape endpoint) to validate exact attribute names, confirm temporality, and fill unknowns listed in `03_apache-http-server_state.yaml`.
3. **Stage 3 (dashboard build):** Use `02_apache-http-server_dashboard_plan.yaml` as the authoritative input to `_build_apache-http-server.py`. Run quality gates before push.
4. **Stage 4 (log intelligence):** Wire access log and error log parsing (see "Log intelligence" section below) to complement metric coverage — error rates come from logs, not from the apache receiver.

The metrics CSV (`01_`) is the single source of truth for what to chart. The dashboard plan YAML (`02_`) is the authoritative layout spec. The state YAML (`03_`) tracks what is confirmed vs inferred. The memory file (`04_`) is the carry-forward summary for future sessions.

---

## What it is and what "good" looks like

Apache HTTP Server (httpd) is the most widely deployed open-source web server. It serves static files, proxies requests to upstream application servers, terminates TLS, and optionally runs embedded scripting (mod_php, mod_wsgi). In modern deployments it is commonly fronted by a load balancer and runs inside Kubernetes pods or bare-metal hosts.

### What "good" looks like for Apache

| Signal | Healthy baseline | Warning threshold | Critical threshold |
|---|---|---|---|
| Worker utilization | < 60 % busy | 60–80 % | > 80 % (saturation imminent) |
| Request rate | Stable or growing with traffic | Sudden drop (> 30 % from baseline) | Near-zero during expected traffic |
| Request time (apache.request.time rate) | < 200 ms p95 per worker | 200–500 ms | > 500 ms sustained |
| 5xx error rate (log-derived) | < 0.1 % of requests | 0.1–1 % | > 1 % |
| 4xx error rate (log-derived) | < 2 % of requests | 2–5 % | > 5 % sustained |
| Async keepalive connections | < 50 % of MaxRequestWorkers | 50–70 % | > 70 % (event MPM connection leak risk) |
| CPU load (apache.cpu.load) | < 50 % | 50–80 % | > 80 % |
| Server uptime | Increasing | Any restart = alert | Multiple restarts in window |

Apache running the **event MPM** (default since Apache 2.4) separates connection handling from request processing. Keepalive connections are held by lightweight async threads, so `apache.connections.async{keepalive}` can be high without saturating workers. The correct saturation metric is `apache.workers{workers_state=busy}` / (`busy` + `idle`).

---

## Key concepts

### Glossary

| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| MPM | Multi-Processing Module. Controls how Apache handles concurrent connections. | Determines concurrency model — prefork (process), worker (thread), event (async). | saturation |
| event MPM | Apache's default MPM since 2.4. Uses async I/O for keepalive connections. | Idle async keepalives don't consume a worker slot; saturation = busy workers, not total connections. | saturation, connections |
| prefork MPM | One process per connection. No threads. | Higher memory usage; MaxRequestWorkers = max concurrent connections. | saturation |
| worker MPM | Hybrid: multiple processes, multiple threads per process. | Better concurrency than prefork with lower memory than one-process-per-connection. | saturation |
| MaxRequestWorkers | Hard limit on simultaneous requests Apache will serve. | The primary saturation ceiling. Formerly called MaxClients. | saturation |
| ServerLimit | Maximum number of processes (prefork) or threads (worker/event). | Absolute ceiling; requires httpd restart to change. | saturation |
| mod_status | Apache module exposing real-time server status at `/server-status`. | Source of all OTel apache receiver metrics. Must be enabled and accessible. | telemetry |
| Scoreboard | Internal Apache data structure tracking worker slot state. | Each slot maps to one possible connection. Slot states reveal what workers are doing. | scoreboard-detail |
| Busy worker | A worker slot actively processing a request (reading, sending, etc.). | Used in saturation calculation. Rises toward MaxRequestWorkers under load. | saturation, availability |
| Idle worker | A worker slot available to accept new requests. | Headroom metric. Should stay > 20 % of total under normal load. | saturation |
| Keepalive slot | Async connection waiting for next request on a persistent HTTP connection. | With event MPM, does not block a worker. High keepalive = normal. | connections |
| Scoreboard state: open | Slot not yet assigned to any connection. | Represents maximum additional concurrency available above current MaxRequestWorkers-in-use. | scoreboard-detail |
| Scoreboard state: waiting | Slot assigned but idle (listening for request). | Normal healthy idle state. | scoreboard-detail |
| Scoreboard state: reading | Slot reading the incoming request headers/body. | Short duration expected. Prolonged = slow clients or large uploads. | scoreboard-detail |
| Scoreboard state: sending | Slot writing response to client. | The primary "active work" state. High sustained value = throughput load. | scoreboard-detail |
| Scoreboard state: dnslookup | Slot performing DNS resolution. | Should be near zero. Non-zero = DNS latency impacting request handling. | scoreboard-detail |
| Scoreboard state: closing | Slot closing the connection. | Brief transition state. High value = connection teardown bottleneck. | scoreboard-detail |
| Scoreboard state: logging | Slot writing to access log. | Brief. High value = logging I/O bottleneck. | scoreboard-detail |
| Scoreboard state: finishing | Slot performing graceful shutdown cleanup. | Non-zero during graceful restarts. | scoreboard-detail |
| Scoreboard state: idle_cleanup | Slot being cleaned up after idle timeout. | Brief. High sustained = aggressive keepalive timeout cycling. | scoreboard-detail |
| apache.request.time | Cumulative monotonic counter of total milliseconds spent processing requests. | Rate gives average throughput time across all workers (not per-request latency). | throughput |
| apache.traffic | Cumulative bytes transferred. | Rate gives bandwidth in B/s. | throughput |
| apache.requests | Cumulative total requests handled. | Rate gives requests/second. | throughput |
| apache.cpu.load | Gauge: current CPU utilization percentage for the httpd process. | High CPU with low request rate = inefficiency. | availability |
| apache.connections.async | Async connection count by state (writing, keepalive, closing). | Event MPM specific. High keepalive is normal; high closing may indicate client issues. | connections |
| CLF | Common Log Format. Standard Apache access log format. | Used for log parsing to derive 4xx/5xx error rates. | errors |
| Combined Log Format | CLF + Referer + User-Agent fields. | Most common real-world format. Enables referrer/UA analysis. | errors |
| VirtualHost | Apache configuration block for a named site. | Multiple VirtualHosts on one Apache instance = per-site metrics not natively separated in OTel receiver. | cardinality |
| mod_proxy | Apache reverse proxy module. | Upstream errors appear as 5xx in access logs. Upstream health is not directly exposed via mod_status. | errors |

### Concept Map

```
Client -> TCP connection -> event MPM listener (why: event MPM handles keepalives async)
event MPM listener -> worker thread assignment (why: only active requests consume worker slots)
worker thread -> request parsing -> scoreboard state: reading (why: slot transitions on request receive)
worker thread -> response generation -> scoreboard state: sending (why: slot transitions on response send)
worker thread -> access log write -> scoreboard state: logging (why: brief I/O state before slot release)
worker thread -> slot release -> scoreboard state: waiting (why: slot returns to idle pool)
apache.workers{busy} -> saturation numerator (why: busy = slots actively processing requests)
apache.workers{idle} -> saturation denominator complement (why: idle = headroom remaining)
apache.workers{busy} / (busy + idle) -> Worker Utilization % (why: primary saturation KPI)
Worker Utilization > 80% -> MaxRequestWorkers ceiling approached (why: no headroom for traffic spike)
MaxRequestWorkers -> ServerLimit (why: ServerLimit is the absolute ceiling requiring restart)
apache.scoreboard{open} -> unallocated capacity (why: open slots not yet assigned to workers)
apache.scoreboard{waiting} -> allocated idle capacity (why: worker exists but not processing)
apache.scoreboard{keepalive} -> async keepalive connections (why: event MPM holds these without blocking workers)
apache.scoreboard{dnslookup} -> DNS resolution in progress (why: spike = DNS degradation impacting latency)
apache.requests rate -> requests/second (why: primary throughput signal)
apache.traffic rate -> bytes/second (why: bandwidth consumption signal)
apache.request.time rate -> aggregate processing time rate (why: proxy for average request handling load)
apache.cpu.load -> process-level CPU % (why: complements request rate for efficiency analysis)
apache.connections.async{keepalive} -> persistent HTTP/1.1 + HTTP/2 clients (why: event MPM async count)
apache.connections.async{writing} -> connections currently writing response (why: active response I/O)
apache.connections.async{closing} -> connections in teardown (why: high = connection close bottleneck)
apache.uptime rate -> near-zero normal; spike to negative = restart detected (why: cumulative uptime resets on restart)
mod_status endpoint -> OTel apache receiver scrapes (why: all apache.* metrics originate here)
OTel apache receiver -> Tsuga ingest pipeline (why: telemetry path for apache.* metrics)
access log -> log shipper -> Tsuga log routes (why: 4xx/5xx errors come from logs not mod_status)
error log -> log shipper -> Tsuga log routes (why: startup errors, module failures in error log)
context.env -> global dashboard filter (why: separates prod/staging/dev instances)
context.team -> global dashboard filter (why: ownership routing for alert triage)
context.scope.name -> per-instance filter (why: server.address from OTel resource attributes)
VirtualHost -> single apache.* metric stream (why: OTel receiver does not disaggregate by vhost natively)
```

### Entities and dimensions

| Entity / Dimension | Why useful | Cardinality risk | Safe top-N |
|---|---|---|---|
| Instance (server.address + server.port) | Per-host breakout essential for fleet debugging | Low — typically 1–20 instances per team | All |
| Environment (context.env) | Separates prod from staging/dev | Very low (2–4 values) | All |
| Team (context.team) | Ownership routing; alert assignment | Low (5–20 teams) | All |
| MPM type | Different saturation profiles per MPM | Static per host (1 value) | N/A |
| workers_state (busy/idle) | Core saturation split | 2 values — safe | All |
| scoreboard_state | Detailed slot state breakdown | 12 values — safe | All |
| connection_state (writing/keepalive/closing) | Async connection breakdown | 3 values — safe | All |
| cpu_level (self/children) | CPU attribution to parent/child processes | 2 values — safe | All |
| cpu_mode (system/user) | Kernel vs user CPU split | 2 values — safe | All |
| VirtualHost name | Per-site breakout | Medium — depends on config (1–50+) | Top 10 |
| HTTP status code (log-derived) | Error rate breakdown | Low for grouped (1xx/2xx/3xx/4xx/5xx) | All grouped |
| HTTP method (log-derived) | GET/POST/PUT/DELETE split | Very low (4–8 common values) | All |
| Request URI prefix (log-derived) | Top endpoints by traffic/error | High — unbounded URI space | Top 20 |

### Tsuga field mapping

| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| server.address (OTel resource attribute) | context.scope.name or context.server.address | Must-exist (instance identification) |
| server.port (OTel resource attribute) | context.server.port | Optional (disambiguates multi-port) |
| deployment.environment (OTel resource attribute) | context.env | Must-exist |
| service.name (OTel resource attribute) | context.service.name | Must-exist |
| team label (K8s pod label or static config) | context.team | Must-exist |
| workers_state attribute | N/A — filter in query | N/A |
| scoreboard_state attribute | N/A — filter in query | N/A |
| connection_state attribute | N/A — filter in query | N/A |

---

## Golden signals

### Traffic (Throughput)

- **Primary metric:** `apache.requests` (cumulative sum, rate → req/s)
- **Secondary metric:** `apache.traffic` (cumulative sum, rate → B/s)
- **Derived:** Request rate per instance; bandwidth per instance
- **What to look for:** Request rate drop > 30 % from baseline without a corresponding upstream change is a leading indicator of worker saturation or process crash.

### Errors

- **Primary source:** Access logs (4xx/5xx HTTP status codes) — NOT available from apache receiver metrics
- **Secondary source:** Apache error log (startup failures, module errors, misconfiguration)
- **Derived:** 5xx rate (%), 4xx rate (%), error rate trend
- **What to look for:** 5xx spike = upstream proxy failure or Apache internal error. 4xx spike = client request pattern change or auth/ACL misconfiguration.
- **Important:** The OTel apache receiver does NOT export per-status-code counters. Error observability requires log routing.

### Latency

- **Primary metric:** `apache.request.time` (cumulative sum ms, rate → ms consumed per second across all workers)
- **Derived:** Average request processing time = apache.request.time rate / apache.requests rate (ms/req)
- **What to look for:** Rising request time with stable request rate = upstream application slowing down. Rising request time AND rising request rate = normal load growth.
- **Limitation:** This is aggregate latency across all workers, not a per-request histogram. No P95/P99 available from mod_status alone.

### Saturation

- **Primary metric:** `apache.workers{workers_state=busy}` / (`apache.workers{busy}` + `apache.workers{idle}`) — Worker Utilization %
- **Secondary metric:** `apache.scoreboard{scoreboard_state=open}` — remaining unallocated capacity
- **Tertiary metric:** `apache.connections.async{connection_state=keepalive}` — async keepalive pressure (event MPM)
- **What to look for:** Worker utilization > 80 % sustained = approach to MaxRequestWorkers limit. New requests will queue or be refused when limit is hit. Open scoreboard slots near zero = absolute ceiling reached.

---

## Telemetry sources

| Source | Transport | Metrics | Logs | Traces | Notes |
|---|---|---|---|---|---|
| OTel apache receiver | HTTP pull from `/server-status?auto` | Yes (`apache.*`) | No | No | Requires `mod_status` enabled; `ExtendedStatus On` for cpu/request.time |
| Apache access log | File / stdout (K8s) | No | Yes (CLF / Combined) | No | Contains HTTP status codes, latency per-request, bytes, URI |
| Apache error log | File / stdout (K8s) | No | Yes | No | Contains startup errors, module failures, AH-prefixed error codes |
| mod_status HTML | Browser / synthetic check | Partial | No | No | Human-readable; not machine-parseable for OTel |
| OTel host metrics receiver | Host-level scrape | Partial (CPU, memory, disk) | No | No | Complements apache.* for host-level resource context |

---

## Log intelligence (Stage 4 handoff)

### Access log format

**Common Log Format (CLF):**
```
%h %l %u %t \"%r\" %>s %b
```
Example: `192.168.1.1 - frank [10/Oct/2025:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326`

**Combined Log Format (most common in production):**
```
%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\"
```

**Extended with latency (recommended for Stage 4):**
```
%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\" %D
```
`%D` = time to serve request in microseconds. Parse and convert to ms for latency histograms.

### Error log format

```
[DayOfWeek Mon DD HH:MM:SS.usec YYYY] [module:level] [pid PID] message
```
Error codes use `AH` prefix (e.g., `AH00163`, `AH01215`). Filter on `[error]` or `[crit]` severity for alerting.

### Candidate query filters

| Precision | Filter string |
|---|---|
| Precise (service name) | `service.name:apache OR service.name:httpd` |
| Precise (scope name) | `scope.name:apache-http-server` |
| Fallback | `apache` |
| 5xx errors | `status:[500 TO 599]` (if status field extracted) |
| 4xx errors | `status:[400 TO 499]` |
| Error log only | `log.file.path:*error_log* OR log.file.path:*error.log*` |

### Attribute mapping hints

| Log field | OTel semantic convention | Tsuga field |
|---|---|---|
| %h (remote IP) | client.address | context.client.address |
| %u (auth user) | enduser.id | context.user.id |
| %r (request line) | http.request.method + url.path + network.protocol.version | context.http.method |
| %>s (status code) | http.response.status_code | context.http.status_code |
| %b (response bytes) | http.response.body.size | context.http.response.bytes |
| %{Referer}i | http.request.header.referer | context.http.referer |
| %D (microseconds) | http.server.request.duration | context.http.duration_us |

### Parsing risks

- Log format varies by VirtualHost and Apache version — validate format string against actual log lines before building parser rules.
- `%b` reports `-` (not `0`) for zero-byte responses (e.g., 304 Not Modified). Parser must handle null/dash.
- `%t` uses Apache's own time format (not ISO 8601). Requires custom time parsing: `[%d/%b/%Y:%H:%M:%S %z]`.
- Rotated logs (logrotate or piped logging) may cause brief gaps in log stream.
- K8s deployments typically write access log to stdout/stderr — ensure log shipper is configured to parse structured JSON or raw CLF from pod logs.

---

## Caveats and footguns

- **[availability]** `apache.uptime` is a monotonic cumulative sum. A restart resets the counter, causing a rate-spike and then near-zero rate. Do not alert on rate; alert on the raw value dropping near zero or resetting.
- **[availability]** `mod_status` must be enabled (`LoadModule status_module`) and `ExtendedStatus On` must be set for `apache.cpu.time`, `apache.cpu.load`, and `apache.request.time` to be populated. Without `ExtendedStatus`, these metrics return zero or are absent.
- **[saturation]** `MaxRequestWorkers` is NOT exposed as a metric by the apache receiver. You cannot compute worker utilization as a percentage of a known ceiling without querying the Apache config or setting it as a custom label/annotation.
- **[saturation]** Worker utilization denominator uses `busy + idle` (which equals current active workers), not `MaxRequestWorkers`. This means the saturation % can appear lower than reality if workers have not all been spawned yet (Apache spawns workers lazily up to MinSpareWorkers/MaxSpareWorkers).
- **[saturation]** With prefork MPM, `apache.workers{busy}` directly equals active requests. With event MPM, a single worker thread can handle many keepalive connections asynchronously — `apache.connections.async{keepalive}` reflects this, and busy workers remain low even under high keepalive load.
- **[connections]** `apache.current_connections` is a non-monotonic sum (cumulative but can decrease). Treat as a gauge for dashboarding.
- **[connections]** `apache.connections.async` is only meaningful with the event MPM. On prefork, this metric is zero. Including it in dashboards without MPM context can be misleading.
- **[scoreboard-detail]** `apache.scoreboard{scoreboard_state=open}` represents slots that have not yet been assigned to any worker — distinct from `waiting` (assigned but idle). `open` slots shrink as Apache spawns more workers up to MaxRequestWorkers.
- **[scoreboard-detail]** The attribute key is `scoreboard_state` (underscore), NOT `scoreboard.state` (dot). Verify in Stage 2 against live metric labels.
- **[scoreboard-detail]** The attribute key for workers is `workers_state` (underscore), NOT `workers.state` (dot). Verify in Stage 2 against live metric labels.
- **[throughput]** `apache.requests` and `apache.traffic` are monotonic cumulative sums. Always use `rate` post-function or `per-second` in Tsuga. Never plot raw cumulative values on a timeseries.
- **[throughput]** `apache.request.time` rate gives total milliseconds consumed per second across ALL workers collectively — not average per-request latency. Divide by `apache.requests` rate to get average request latency in ms.
- **[errors]** The apache receiver exports NO error rate metrics. 4xx and 5xx rates MUST come from access log routing. Building an "Errors" dashboard section without log intelligence wired up will result in empty panels.
- **[errors]** Apache error log entries are not in JSON by default. A log parsing rule (regex or grok) is required to extract severity, module, and error code fields.
- **[availability]** `apache.cpu.load` is a percentage of total CPU time consumed by httpd — it can exceed 100 % on multi-core hosts if Apache uses multiple cores. Not directly comparable to `top`-style per-core percentage.
- **[availability]** `apache.load.1`, `apache.load.5`, `apache.load.15` are system-level load averages from `/proc/loadavg` (Linux) as reported by Apache, NOT httpd-specific CPU load. They reflect total system load and should be interpreted as such.
- **[availability]** `apache.cpu.time` uses unit `{jiff}` (jiffy = 10ms on most Linux kernels). This is a cumulative counter; use rate for meaningful display.
- **[throughput]** `apache.traffic` counts bytes at the application layer. It does not include TLS overhead, HTTP/2 header compression savings, or network-level retransmissions.
- **[scoreboard-detail]** VirtualHost disaggregation is NOT natively available from mod_status or the OTel apache receiver. All apache.* metrics are aggregate across all VirtualHosts on the instance.
- **[saturation]** On K8s, each pod runs a separate Apache instance. Fleet-wide saturation requires summing across pods (use `sum` aggregation in Tsuga, then group by instance for breakout).
- **[availability]** A scrape failure by the OTel Collector (e.g., mod_status endpoint unreachable) will cause all apache.* metrics to go absent. Distinguish "server down" from "scrape misconfiguration" by cross-referencing OTel Collector health metrics.
- **[connections]** `apache.connections.async{writing}` overlaps conceptually with `apache.scoreboard{sending}` but counts at the TCP connection level vs scoreboard slot level. They are not identical and should not be summed.

---

## Confirmed Tsuga prefixes

| Prefix | Status | Source | Estimated metric count |
|---|---|---|---|
| `apache` | **CONFIRMED** | OTel Collector Contrib `apachereceiver` metadata.yaml | 12 metric names |

Specific confirmed metric names (exact strings from metadata.yaml):
- `apache.uptime`
- `apache.current_connections`
- `apache.workers`
- `apache.requests`
- `apache.traffic`
- `apache.scoreboard`
- `apache.connections.async`
- `apache.cpu.load`
- `apache.cpu.time`
- `apache.request.time`
- `apache.load.1`
- `apache.load.5`
- `apache.load.15`

Confirmed attribute names (exact strings from metadata.yaml):
- `workers_state` with values: `busy`, `idle`
- `scoreboard_state` with values: `open`, `waiting`, `starting`, `reading`, `sending`, `keepalive`, `dnslookup`, `closing`, `logging`, `finishing`, `idle_cleanup`, `unknown`
- `connection_state` with values: `writing`, `keepalive`, `closing`
- `cpu_level` with values: `self`, `children`
- `cpu_mode` with values: `system`, `user`

---

## Discovery status

**Stage 2 discovery: PENDING**

Discovery has not been performed against a live Apache HTTP Server instance. All metric names and attribute values are sourced from the OTel Collector Contrib `apachereceiver/metadata.yaml` (confirmed) or inferred from Apache documentation (noted where applicable).

Priority verification items for Stage 2:
1. Confirm `workers_state` vs `state` as actual label key on live metrics
2. Confirm `scoreboard_state` vs `state` as actual label key on live metrics
3. Confirm `apache.requests` and `apache.traffic` temporality (expected: cumulative monotonic)
4. Confirm `apache.uptime` temporality (expected: cumulative monotonic — resets on restart)
5. Confirm `apache.current_connections` behaves as non-monotonic sum in practice
6. Verify `ExtendedStatus On` is required for `apache.cpu.*` and `apache.request.time`
7. Verify whether `server.address` maps to `context.scope.name` or `context.server.address` in Tsuga
8. Check if mod_status VirtualHost disaggregation is available via `?server=vhost_name` parameter

---

## Top sources

1. **OTel apache receiver metadata.yaml** — https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/apachereceiver/metadata.yaml — authoritative source for all `apache.*` metric names, types, units, and attribute values
2. **OTel apache receiver README** — https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/apachereceiver — configuration reference for the receiver (endpoint, collection_interval, auth)
3. **Apache mod_status documentation** — https://httpd.apache.org/docs/current/mod/mod_status.html — authoritative source for worker scoreboard states and mod_status endpoint format
4. **Apache MPM documentation (event)** — https://httpd.apache.org/docs/current/mod/event.html — event MPM architecture, async connection handling, MaxRequestWorkers behavior
5. **Apache MPM documentation (prefork)** — https://httpd.apache.org/docs/current/mod/prefork.html — prefork process model; MaxRequestWorkers = max concurrent requests
6. **Apache core directives** — https://httpd.apache.org/docs/current/mod/core.html — MaxRequestWorkers, ServerLimit, StartServers, MinSpareThreads, MaxSpareThreads
7. **Apache log formats** — https://httpd.apache.org/docs/current/mod/mod_log_config.html — complete format string reference for access log parsing (CLF, Combined, custom)
8. **Apache error log format** — https://httpd.apache.org/docs/current/logs.html — error log structure, AH error codes, severity levels
9. **OpenTelemetry semantic conventions (HTTP)** — https://opentelemetry.io/docs/specs/semconv/http/ — attribute naming for HTTP request/response fields in log and trace data
10. **OTel Collector Contrib apachereceiver source** — https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/apachereceiver — full receiver implementation including scraper logic and metric construction
11. **Apache performance tuning guide** — https://httpd.apache.org/docs/current/misc/perf-tuning.html — MaxRequestWorkers tuning recommendations, keep-alive timeout guidance
12. **Prometheus apache_exporter** — https://github.com/Lusitaniae/apache_exporter — alternative metric source; useful for cross-referencing metric semantics with OTel receiver
