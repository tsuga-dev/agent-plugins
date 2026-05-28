# HAProxy Integration Context Bundle

## Metadata
**Technology:** HAProxy
**Deployment:** self-hosted
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** mixed
**Integration scope:** core service only
**Primary use-case:** reliability and performance

## How to use this bundle
- Use `01_haproxy_metrics.csv` as the source of truth for metric names, units, temporality assumptions, and safe query behavior.
- Use `02_haproxy_dashboard_plan.yaml` as the implementation blueprint for sections, widgets, derived signals, notes, triage chains, and playbooks.
- Use `03_haproxy_state.yaml` as the machine-readable bundle state (stage outcomes, corrections, access-method audit, and unresolved unknowns).
- Use `04_haproxy_memory.md` for consolidated Stage 2/3 memory (reconciliation decisions, access-method history, and created dashboard outcomes).
- Stage 2 will reconcile all metric names, context fields, and temporality against live Tsuga data and patch this bundle.

## What it is and what "good" looks like

### Confirmed by sources
- HAProxy is a multi-threaded, event-driven proxy that exposes frontend, backend, listener, and server traffic/health counters through `show stat` and Prometheus interfaces. [S1][S2][S3][S5]
- The native Prometheus service is enabled via `http-request use-service prometheus-exporter` and can export scope-filtered metrics; high-cardinality configurations can be expensive to scrape. [S2][S5][S6]
- HAProxy runtime stats include queue depth (`qcur`), active sessions (`scur`), byte counters (`bin`,`bout`), request/response errors (`ereq`,`eresp`), status code classes (`hrsp_5xx`), and backend/server health indicators. [S1][S3]
- The OpenTelemetry HAProxy receiver maps these runtime fields into `haproxy.*` metrics and marks many core counters as cumulative sums. [S7][S8]
- "Good" operational state is stable request/session throughput, low queue pressure, low connect/request/response error growth, and healthy backend/server availability with no sustained downtime growth. [S1][S3][S7]
- Paging intent in dashboard form: rapidly distinguish traffic surge, upstream dependency degradation, and HAProxy saturation before user-visible outage widens.

### Best-practice inference
- Incident shape 1: **Backend degradation**. Signals: error counters rise (`connections.errors`, `responses.errors`), backend downtime/check-fail metrics rise, request throughput remains non-zero. Start in `errors-failures`.
- Incident shape 2: **Saturation under load**. Signals: queued requests rise, session counts push toward limits, connection rates spike. Start in `saturation-capacity`.
- Incident shape 3: **Latency creep before failures**. Signals: session/connect/queue/response average times drift up while hard errors remain moderate. Start in `latency-performance`.
- Dashboard success criteria for on-call: one glance for health posture, one click for per-proxy/per-service attribution, and explicit missing-data handling when optional metrics are disabled.

## Key concepts

### Glossary

| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| Frontend | HAProxy entrypoint that accepts client traffic | First place to confirm inbound load and denied sessions | traffic-throughput |
| Backend | HAProxy upstream pool definition | Tracks upstream availability, queueing, and failures | availability-health |
| Server | Individual backend target | Isolates failing instances within a backend | availability-health |
| Listener | Bound socket handling accepted connections | Identifies edge pressure and connection handling issues | traffic-throughput |
| Session | HAProxy end-to-end transaction lifecycle | Used for active load and saturation posture | saturation-capacity |
| Queue (`qcur`) | Requests waiting for backend assignment | Early warning of capacity shortfall | saturation-capacity |
| Active sessions (`scur`) | Current in-flight sessions | Core concurrency signal | saturation-capacity |
| Session rate (`rate`) | Sessions per second over recent second | Burst and trend signal | traffic-throughput |
| Request rate (`req_rate`) | HTTP requests per second over recent second | Throughput and surge detection | traffic-throughput |
| Connect errors (`econ`) | Failed attempts to connect to backend | Dependency/network failure indicator | errors-failures |
| Request errors (`ereq`) | Request parsing/processing errors | Client/input or proxy-path issues | errors-failures |
| Response errors (`eresp`) | Response path errors including server aborts | Upstream failure or midstream abort indicator | errors-failures |
| Denied requests (`dreq`) | Security/ACL-denied requests | Policy-driven rejects vs availability failures | errors-failures |
| Denied responses (`dresp`) | Security/ACL-denied responses | Policy post-processing effects | errors-failures |
| Redispatch (`wredis`) | Request re-routed to alternate server | Often indicates unstable upstream targets | errors-failures |
| Retry (`wretr`) | Backend connection retry event | Retry amplification can hide/worsen incidents | errors-failures |
| Check failures (`chkfail`) | Failed health checks while server considered up | Predictive signal for backend deterioration | availability-health |
| Downtime | Cumulative downtime seconds | Indicates sustained unavailability over time | availability-health |
| Active/backup servers (`act`,`bck`) | Count of active or backup backend servers | Capacity envelope and failover posture | availability-health |
| Session limit (`slim`) | Configured max sessions | Reference denominator for utilization | saturation-capacity |
| Average queue/connect/response/session time | Rolling latency-like gauges over recent requests | Triage whether pain is wait, connect, or serve time | latency-performance |
| `status_code` attribute | OTel dimension for 1xx/2xx/3xx/4xx/5xx/other | Enables error-rate formulas without separate metrics | errors-failures |
| `haproxy.proxy_name` attribute | OTel proxy-level identity | Primary bounded group-by for ownership/blast radius | all |
| `haproxy.service_name` attribute | OTel service role (FRONTEND/BACKEND/listener/server name) | Split by traffic role and pipeline stage | all |

[S1][S3][S7][S8]

### Entities and dimensions

| Entity/Dimension | Why useful | Cardinality risk | Safe top-N | Do NOT group-by guidance |
|---|---|---|---|---|
| `context.env` | Environment boundary for prod/staging | Low | 5 | Always keep as global filter, not deep chart split |
| `context.team` | Ownership routing during incidents | Low | 10 | Avoid as first diagnostic axis for technical root cause |
| `context.proxy` | Stable frontend/backend/listener/server identity in discovered Tsuga data | Medium | 20 | Do not combine with high-card path/client labels |
| `context.service.name` | Service-level ownership and blast-radius split | Medium | 20 | Avoid mixing with raw server address in overview KPIs |
| `context.server.address` | Socket/server endpoint attribution | Medium | 20 | Can explode with ephemeral addresses in dynamic configs |
| `context.service.name` | Organization service boundary | Medium | 20 | Do not pair with pod UID in same chart |
| `context.scope.name` | Fallback stable scope when proxy_name missing | Medium | 20 | Use as fallback, not alongside proxy_name unless needed |
| `context.code` | HTTP class/code slices on response totals | Low | 6 | Keep bounded to class-level, avoid raw status if absent |
| `context.k8s.cluster.name` | Multi-cluster blast radius | Low-Medium | 10 | Skip for non-k8s deployments |
| `context.k8s.namespace.name` | Tenant/workload partitioning | Medium | 20 | Avoid in top KPI widgets |
| `context.host` | Host-level hotspot detection | Medium-High | 20 | Prefer scope/service for default views |
| `context.cloud.region` | Regional failure domain | Low | 12 | Only if consistently enriched |
| `context.cloud.account.id` | Multi-account segmentation | Medium | 10 | Avoid if single-account deployment |

### Tsuga field mapping

| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| `proxy_name` / `pxname` | `context.proxy` | Optional (confirmed present) |
| `svname` (server/listener/backend target) | `context.service.name` | Optional (confirmed present) |
| `addr` | `context.server.address` | Optional (confirmed present) |
| Response code class/code labels | `context.code` | Optional (confirmed on `*_http_responses_total`) |
| Frontend/backend/server role identity | `context.service.name` | Optional |
| Runtime socket node identity | `context.scope.name` | Optional fallback |
| Service tag from collector enrichment | `context.service.name` | Optional |
| Environment tag (org standard) | `context.env` | Must-exist |
| Team tag (org standard) | `context.team` | Must-exist |
| Kubernetes cluster enrichment | `context.k8s.cluster.name` | Optional |
| Kubernetes namespace enrichment | `context.k8s.namespace.name` | Optional |
| Cloud region enrichment | `context.cloud.region` | Optional |
| Cloud account enrichment | `context.cloud.account.id` | Optional |

### Confirmed by sources
- `proxy_name`, `service_name`, and `addr` are emitted as HAProxy receiver resource attributes. [S7]
- `status_code` attribute is documented on `haproxy.requests.total`. [S7]

### Best-practice inference
- Stage 2 discovery confirmed Tsuga key shape uses `context.proxy`, `context.service.name`, `context.server.address`, and `context.code` (on response metrics), not `context.haproxy.*`.
- `context.scope.name` remains a practical fallback when proxy/service labels are sparse.

## Golden signals

### Confirmed by sources
| Signal | What it means for HAProxy | Typical degradation causes | Best telemetry sources | What people page on | Section questions |
|---|---|---|---|---|---|
| Traffic | Incoming and forwarded load level at frontend/listener/backend surfaces | Traffic spikes, reconnect storms, uneven proxy distribution | `haproxy.sessions.rate`, `haproxy.requests.rate`, `haproxy.connections.rate`, `haproxy.*.total` [S3][S7][S8] | Sustained throughput jump with concurrent queue growth | Is ingress load normal? Which proxy/service absorbs most traffic? |
| Errors | Failures across connect/request/response/security paths | Upstream dependency failure, ACL/policy rejects, malformed request bursts | `connections.errors`, `requests.errors`, `responses.errors`, denied/retry/redispatch counters [S1][S3][S7] | Error-rate acceleration or retries climbing while throughput stays high | Are failures upstream-connect, request parsing, or response-path dominant? |
| Latency | Time spent waiting/connecting/responding over rolling windows | Backend slowness, network degradation, queue buildup | `sessions.average`, `requests.average_time`, `connections.average_time`, `responses.average_time` [S3][S7] | Session/response time drift with stable load | Is delay queueing, connect, or server response time? |
| Saturation | Concurrency and queue pressure vs configured limits | Session limit pressure, backend capacity collapse, retry amplification | `sessions.count`, `sessions.limit`, `requests.queued`, `active/backup`, session limit stats [S1][S3][S7] | Queue growth and utilization high enough to threaten drops/timeouts | Are we running out of session/queue capacity? Is failover pool sufficient? |

### Best-practice inference
- For HAProxy, connect/request/response error families are often more operationally useful than generic CPU/memory because they expose dependency path failure directly.
- Queue and session-limit ratios should be treated as first-class saturation KPIs, not secondary charts.

## Telemetry sources

### Confirmed by sources
| Source type | How collected | What it provides | Pros/cons | Common pitfalls |
|---|---|---|---|---|
| Runtime API `show stat` / stats socket | CLI/socket polling (`stats socket`, `show stat`, CSV/typed/json) | Canonical frontend/backend/server/listener counters and state | Most complete low-level data; requires socket access and secure permissions | Misreading cumulative counters as instant rates; stats socket not exposed [S1][S2] |
| Built-in Prometheus exporter (PROMEX) | `http-request use-service prometheus-exporter` and scrape `/metrics` | Native Prometheus metric families (`haproxy_frontend_*`, `haproxy_backend_*`, etc.) | No sidecar needed; broad ecosystem compatibility; can filter scopes/metrics | High cost on huge configs; more verbose/slower than CSV; optional extra counters can explode cardinality [S2][S5][S6] |
| Prometheus retired external exporter | Scrapes `?stats;csv` and re-exports | Compatibility path for legacy deployments | Useful in old setups | Officially retired; migrate to built-in exporter [S9] |
| OpenTelemetry HAProxy receiver | Polls socket or HTTP stats endpoint | Normalized `haproxy.*` metrics with documented attributes and optional metric toggles | Easy OTel pipeline alignment; explicit metric catalog | Many metrics marked development/beta; optional metrics disabled by default unless enabled [S7][S8] |
| HAProxy stats dashboard/UI | `stats enable` + `stats uri` | Human-readable point-in-time health status | Quick operator visibility | Not machine-optimized; requires auth/hardening | [S2][S10] |

### Best-practice inference
- "No data" in optional metrics usually means disabled metric family or disabled HAProxy feature, not necessarily healthy zero.
- In mixed telemetry deployments, prefer one canonical family (`haproxy_*` OTel or `haproxy_frontend_*` PROMEX) per widget to avoid double-counting.

## Caveats and footguns
- **[traffic-throughput]** `sessions.rate` and `requests.rate` are already per-second gauges; applying rate/per-second again corrupts meaning. (S7)
- **[errors-failures]** `responses.errors` includes server abort behavior; do not interpret as only proxy-generated response faults. (S7)
- **[errors-failures]** Retry and redispatch growth can mask backend instability while user-facing errors still look moderate. (S1, S7)
- **[saturation-capacity]** Queue growth (`qcur`) with flat throughput is a hard saturation warning, not normal burst noise. (S1)
- **[saturation-capacity]** `sessions.count` without `sessions.limit` loses utilization context and causes false calm. (S7)
- **[availability-health]** `downtime` is cumulative and monotonic; it should be shown as rate/increase for recent incidents, not absolute value only. (S7)
- **[availability-health]** `failed_checks` only counts failed checks while server is up; it can miss complete-down periods if interpreted alone. (S7)
- **[latency-performance]** Average time metrics (`ttime`,`qtime`,`ctime`,`rtime`) are rolling averages over recent requests, not percentile latency. (S7)
- **[latency-performance]** Comparing latency averages across proxies with very different traffic mix can mislead triage. (Inference)
- **[errors-failures]** Denied requests/responses may represent policy intent, not outage; pair with config change context before paging. (S1, S2)
- **[traffic-throughput]** Promex can export extra counters and protocol-specific families; enabling all can create heavy scrape payloads. (S5)
- **[traffic-throughput, secondary-signals]** QUIC/H2/H1 metric families are optional and often absent unless those protocol paths are active. (S5, S6)
- **[runtime-operations]** On large configurations, `/metrics` generation can be significantly slower and more verbose than CSV stats. (S5)
- **[runtime-operations]** Missing stats socket or auth misconfiguration causes telemetry blind spots that look like "all zeros" in dashboards. (S2, S9)
- **[availability-health]** Active/backup server counts can change from config or maintenance actions, not only hard failures. (S1)
- **[saturation-capacity]** Connection and session limits are configuration-driven; a low configured limit can make moderate traffic look pathological. (S2)
- **[errors-failures]** Status-class splits from `requests.total` require status_code attribute propagation; without it, class widgets must be gated. (S7)
- **[traffic-throughput]** Grouping by raw address can explode in dynamic service discovery or ephemeral listener setups. (Inference)
- **[runtime-operations]** Mixing OTel `haproxy.*` and Promex `haproxy_frontend_*` in one KPI can double-count the same underlying traffic. (Inference)
- **[latency-performance, saturation-capacity]** Rising queue time with stable connect time usually points to backend processing saturation, not network path failure. (Inference)
- **[availability-health]** "No data" for optional metrics may simply mean those receiver metrics are disabled by default. (S7)
- **[errors-failures]** `connections.errors` and `requests.errors` trace different failure stages; merging them without label context hides root cause. (S1, S7)
- **[traffic-throughput]** Scope/metrics query-string filters in Promex can silently hide expected signals if scrape URI differs across environments. (S5)

## Confirmed Tsuga prefixes
- `haproxy_*` — **CONFIRMED** (225 metrics discovered in Tsuga over 24h window; unioned across paged scans to avoid non-deterministic catalog ordering).
- `haproxy_frontend_*` — **CONFIRMED** (33 metrics discovered).
- `haproxy_backend_*` — **CONFIRMED** (55 metrics discovered).
- `haproxy_server_*` — **CONFIRMED** (58 metrics discovered).

## Discovery status
Discovery: completed in Stage 2.
- `METRICS_FOUND`: 225 HAProxy-prefixed metrics from a 1014-metric catalog (24h window ending 2026-02-17).
- Stage 1 OTel-style names (`haproxy_requests_total`, `haproxy_sessions_count`, etc.) were largely absent; Tsuga uses PROMEX-style families (`haproxy_frontend_*`, `haproxy_backend_*`, `haproxy_server_*`).
- Context keys were corrected to discovered fields: `context.proxy`, `context.service.name`, `context.server.address`, `context.scope.name`, and `context.code` (response metrics).
- Counter temporality for sampled HAProxy counters is `delta`, so dashboard queries were corrected to `sum + per-second`.
- Scalar data spot-checks via MCP `aggregate-scalar` were inconclusive due repeated internal server errors; catalog + metadata evidence was used.

## Top sources
1. https://docs.haproxy.org/2.8/management.html
   Why: canonical architecture and `show stat` CSV field semantics (`qcur`, `scur`, `stot`, `bin`, `bout`, `ereq`, `eresp`, `hrsp_5xx`).
2. https://docs.haproxy.org/2.8/configuration.html
   Why: authoritative configuration of stats socket and native `prometheus-exporter` service hook.
3. https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-contrib/main/receiver/haproxyreceiver/documentation.md
   Why: exact OTel HAProxy metric catalog, units, temporality, and attributes.
4. https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-contrib/main/receiver/haproxyreceiver/README.md
   Why: receiver collection model (socket/HTTP endpoint), defaults, and metric enablement behavior.
5. https://raw.githubusercontent.com/haproxy/haproxy/master/addons/promex/README
   Why: built-in Prometheus exporter behavior, filtering controls, performance caveats, and exported metric families.
6. https://raw.githubusercontent.com/prometheus/haproxy_exporter/master/README.md
   Why: migration guidance and legacy exporter constraints for environments not yet on native exporter.
7. https://www.haproxy.com/documentation/haproxy-configuration-tutorials/alerts-and-monitoring/prometheus/
   Why: official HAProxy tutorial for Prometheus endpoint setup and modern metric families.
8. https://www.haproxy.com/documentation/haproxy-runtime-api/reference/show-stat/
   Why: runtime command reference for traffic statistics retrieval and formats.
9. https://www.haproxy.com/documentation/haproxy-runtime-api/reference/show-info/
   Why: runtime process-level info surface for operational context and runtime posture.
10. https://www.haproxy.com/documentation/haproxy-configuration-tutorials/reliability/health-checks/
    Why: health-check behavior context that influences check-failure, downtime, and backend availability interpretation.

---

**Citation key**
- [S1] https://docs.haproxy.org/2.8/management.html
- [S2] https://docs.haproxy.org/2.8/configuration.html
- [S3] https://www.haproxy.com/documentation/haproxy-runtime-api/reference/show-stat/
- [S4] https://www.haproxy.com/documentation/haproxy-runtime-api/reference/show-info/
- [S5] https://raw.githubusercontent.com/haproxy/haproxy/master/addons/promex/README
- [S6] https://www.haproxy.com/documentation/haproxy-configuration-tutorials/alerts-and-monitoring/prometheus/
- [S7] https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-contrib/main/receiver/haproxyreceiver/documentation.md
- [S8] https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-contrib/main/receiver/haproxyreceiver/README.md
- [S9] https://raw.githubusercontent.com/prometheus/haproxy_exporter/master/README.md
- [S10] https://www.haproxy.com/documentation/haproxy-configuration-tutorials/alerts-and-monitoring/statistics/
