# Envoy Integration Context Bundle

## Metadata
**Technology:** Envoy
**Deployment:** self-hosted
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** mixed
**Integration scope:** core service only
**Primary use-case:** reliability and performance

## How to use this bundle
- Use `01_envoy_metrics.csv` as the source of truth for metric names, units, types, and safe query behavior.
- Use `02_envoy_dashboard_plan.yaml` for the dashboard section and widget blueprint, derived signal formulas, explanation notes, triage chains, and operational playbooks.
- Use `03_envoy_state.yaml` for machine-readable reconciliation status and remaining unknowns.
- Use `04_envoy_memory.md` for human-readable reconciliation and implementation memory.
- Stage 2 creates/refreshes `05_envoy_metric_catalog.csv` as the discovered inventory and context-key curation layer.
- Stage 4 should start with `## Log intelligence (Stage 4 handoff)` in this file and `03_envoy_state.yaml` `log_intel` before building/updating log routes.

## What it is and what "good" looks like

### Confirmed by sources
- Envoy is a high-performance L4/L7 proxy used as a data-plane component for ingress, egress, and service-to-service routing in Kubernetes and non-Kubernetes environments. [S1][S2]
- Envoy exposes rich operational telemetry through `/stats` and `/stats/prometheus`, including upstream request outcomes, connection lifecycle, listener pressure, and server runtime signals. [S1][S3][S4][S5]
- "Good" for core Envoy operations means: healthy upstream host pools, low upstream 5xx/timeout fractions, stable latency (not just stable volume), and no sustained circuit-breaker or overflow pressure. [S3][S6]
- For an SRE triage surface, the fastest route is to split the experience into: availability/health, traffic, errors, latency, saturation, and runtime resource pressure. [S2][S3][S4][S5]
- Common incident shapes are directly visible in Envoy core stats families: upstream dependency failure spikes (`upstream_rq_5xx`, `upstream_rq_timeout`), saturation (`*_overflow`, circuit-breaker open states), and load/latency shifts (`upstream_rq_total`, `upstream_rq_time`). [S3][S6][S7]

### Best-practice inference
- **Incident shape 1: Upstream dependency degradation**
  - Symptom: request volume is steady but `5xx`, `timeout`, and retries climb.
  - Start in section: **Errors & Failures**.
- **Incident shape 2: Proxy saturation before hard failure**
  - Symptom: active connections and pending overflow rise; circuit breakers begin opening.
  - Start in section: **Saturation & Capacity**.
- **Incident shape 3: Latency regression without outright errors**
  - Symptom: success rate looks healthy but mean upstream request time drifts upward.
  - Start in section: **Latency & Performance**.
- High-level paging intent for dashboards: detect user-impacting routing failure early, distinguish upstream dependency issues from Envoy capacity bottlenecks, and direct on-call to the next section without requiring Envoy internals expertise.

## Key concepts

### Glossary

| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| Listener | Socket binding where downstream traffic enters Envoy | Affects listener pressure and accept failures | availability-health, saturation-capacity |
| Filter chain | Ordered processing path selected on listener match conditions | Mismatches can drop or misroute traffic | availability-health |
| HTTP connection manager | L7 HTTP handling component that emits downstream request counters by response class | Basis for downstream request class counters | traffic-volume, errors-failures |
| Cluster | Upstream endpoint group Envoy routes to | Primary unit for upstream success/error telemetry | traffic-volume, errors-failures, latency-performance |
| Endpoint/host | Individual upstream target in a cluster | Health and ejection state drive routing quality | availability-health |
| Circuit breaker | Hard cap on concurrent connections/requests/retries to protect upstreams | When open, predicts request drops/latency spikes | saturation-capacity |
| Outlier detection | Automatic ejection of failing upstream hosts based on error patterns | Reduces healthy host denominator | errors-failures, availability-health |
| Upstream request | Request Envoy sends to dependency cluster | Basis for `upstream_rq_*` families | traffic-volume, errors-failures |
| Downstream request | Request accepted from client side | Basis for `downstream_rq_*` families | traffic-volume |
| Active downstream connections | Current open client connections per listener | Saturation pressure indicator | saturation-capacity |
| Active upstream connections | Current open backend connections per cluster | Backend connection pressure | saturation-capacity |
| Pending overflow | Rejected/overflowed pending upstream requests due to limits | Already request loss, not just warning | saturation-capacity, errors-failures |
| Retry | Envoy reattempt of failed upstream call under retry policy | Can amplify load on unstable dependencies | errors-failures |
| Upstream timeout | Request exceeded configured upstream timeout budget | Contributes to 5xx/user-visible failures | errors-failures, latency-performance |
| Response code class | 2xx/4xx/5xx grouping used in request outcome counters | Fast error class attribution | errors-failures |
| Request time histogram | Distribution of upstream request durations | Early warning for dependency slowness | latency-performance |
| Healthy membership | Count of currently healthy hosts in a cluster | Denominator for many interpretations | availability-health |
| Server live flag | Runtime liveness indicator for Envoy process | Confirms process liveness only | availability-health |
| Heap size / allocated memory | Runtime memory pressure indicators for Envoy process | Resource pressure signal | resource-runtime |
| Admin stats endpoint | `/stats` and `/stats/prometheus` interfaces for telemetry export | Telemetry and ingestion prerequisites | telemetry |
| Stat tags | Envoy mechanism to transform stat names into labels for backends like Prometheus | Group-by and cardinality design | all |
| Hot restart epoch | Generation marker during hot restart; can cause short-lived metric discontinuities | Runtime caveats | resource-runtime |

[S1][S2][S3][S4][S5][S6][S8][S11][S12]

### Concept Map

```text
Client traffic -> enters -> Envoy listener (why: first choke point for downstream availability)
Listener -> routes through -> filter chain / HTTP connection manager (why: request classification and policy application)
HTTP connection manager -> forwards to -> upstream cluster (why: dependency routing boundary)
Upstream cluster -> contains -> upstream hosts/endpoints (why: healthy host pool drives success capacity)
Upstream host health checks -> update -> healthy membership counts (why: denominator for load and failure interpretation)
Healthy membership drop -> increases -> per-host load (why: latency and error risk rise before full outage)
Upstream requests -> produce -> response code class counters (why: fast 2xx/4xx/5xx outcome split)
Upstream requests -> accumulate -> timeout and reset counters (why: dependency-path failure signals)
Retry policy -> triggers -> retry attempts (why: can mask or amplify dependency instability)
Retry attempts -> consume -> retry circuit-breaker budget (why: breaker-open means retries are refused)
Active downstream connections -> consume -> listener/proxy capacity (why: saturation precursor)
Active upstream connections -> consume -> cluster pool capacity (why: backend pressure precursor)
Pending requests -> overflow when -> queue/limit is exceeded (why: immediate request loss signal)
Circuit breaker open state -> blocks -> new requests/connections/retries (why: overload protection already engaged)
Request latency histogram -> reflects -> upstream/service processing health (why: degradation can precede error spikes)
Envoy runtime memory/heap metrics -> reflect -> process resource pressure (why: runtime exhaustion risk)
Service/team/env/cluster context -> maps to -> ownership and blast-radius filters (why: triage routing)
Rollouts/config changes -> alter -> listener/cluster behavior and stat shape (why: sudden metric shifts may be config-driven)
```

### Entities and dimensions

| Entity/Dimension | Why useful | Cardinality risk | Safe top-N | Do NOT group-by guidance |
|---|---|---|---|---|
| `context.env` | Environment split for prod vs non-prod | Low | 5 | Never omit from global filter in shared org dashboards |
| `context.team` | Ownership/triage routing | Low | 10 | Avoid as first investigative split for latency root cause |
| `context.service.name` | Service boundary in mesh/ingress stacks | Medium | 20 | Avoid combining with pod UID in same widget |
| `context.k8s.cluster.name` | Multi-cluster posture and blast radius | Low-Medium | 10 | Do not mix with high-card labels in overview |
| `context.k8s.namespace.name` | Tenant/workload segmentation | Medium | 20 | Avoid on global KPI widgets unless needed |
| `context.scope.name` | Stable instance/workload scope fallback | Medium | 20 | Prefer over ephemeral pod ids when host missing |
| `context.host` | Host-level hotspot detection | Medium-High | 20 | Fallback to `context.scope.name` if absent |
| `context.envoy.cluster_name` | Upstream dependency isolation | Medium | 20 | Avoid cluster+route+pod triple split |
| `context.envoy.listener_name` | Entrypoint diagnosis | Medium | 20 | Do not use for global high-level KPIs |
| `context.response_code_class` | Fast error class attribution | Low | 5 | Use class first; drill into exact code only when needed |
| `context.response_code` | Exact protocol failure signal | High | 20 | Avoid in overview due cardinality and noise |
| `context.envoy.http_conn_manager_prefix` | Distinguishes HCM instances | Medium | 10 | Avoid when prefix is dynamic per route |
| `context.k8s.pod.name` | Pod hotspot and rollout impact | High | 20 | Never in overview top-level KPI widgets |
| `context.instance.id` | Process-specific debugging | High | 20 | Avoid if rotates frequently (autoscale/churn) |

### Tsuga field mapping

| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| `envoy_cluster_name` (Prom labels/tags) | `context.envoy.cluster_name` | Optional — if absent, derive cluster from service/routing metadata |
| `envoy_listener_name` | `context.envoy.listener_name` | Optional — needed for listener-focused saturation views |
| `envoy_http_conn_manager_prefix` | `context.envoy.http_conn_manager_prefix` | Optional — useful where multiple HCM prefixes exist |
| `response_code_class` | `context.response_code_class` | Optional — needed for 2xx/4xx/5xx splits |
| `response_code` | `context.response_code` | Optional — high cardinality, use sparingly |
| `cluster` (generic service mesh tag) | `context.envoy.cluster_name` | Optional — normalize to single key to avoid duplicates |
| `service` | `context.service.name` | Optional — strongly recommended for multi-service meshes |
| `namespace` | `context.k8s.namespace.name` | Optional — expected in k8s deployments but not guaranteed |
| `kubernetes_cluster` | `context.k8s.cluster.name` | Optional — validate real field name in Stage 2 |
| `pod` | `context.k8s.pod.name` | Optional — debug-only, cardinality risk |
| `instance` | `context.scope.name` | Optional — preferred stable fallback where host is absent |
| `host` | `context.host` | Optional — must be validated; not universally present in Envoy telemetry |
| Organization environment tag | `context.env` | Must-exist — declared org standard in `.env` |
| Organization team tag | `context.team` | Must-exist — declared org standard in `.env` |

[S1][S3][S4][S5][S6][S8][S9][S11][S12]

## Golden signals

| Signal | What it means for Envoy | Primary telemetry families | Typical degradation causes | What people page on | Section questions |
|---|---|---|---|---|---|
| **Traffic** | Request and connection workload entering Envoy and forwarded to upstream clusters | `upstream_rq_total`, `downstream_rq_total`, `downstream_cx_total` [S3][S4][S5] | Traffic surges, retry storms, client reconnect churn, uneven load distribution | Sudden request-rate jumps with concurrent latency drift or overflow pressure | Are downstream and upstream volumes aligned? Which clusters/listeners carry disproportionate load? |
| **Errors** | Routing outcomes where requests fail at proxy or upstream dependency boundary | `upstream_rq_5xx`, `upstream_rq_4xx`, `upstream_rq_timeout`, `upstream_rq_pending_overflow`, `downstream_rq_xx` [S3][S4] | Unhealthy host pools, connect failures/timeouts, overload/circuit-breaker pressure, upstream app failures | Sustained 5xx growth, timeout ratio spikes, overflow non-zero under normal load | Are failures dominated by upstream errors, timeouts, or proxy overload? Is retry behavior masking deeper upstream instability? |
| **Latency** | Time spent serving and forwarding requests, especially upstream round-trip latency | `upstream_rq_time` histogram [S3] | Upstream slowness, connection establishment delays, queue buildup before hard failures | Mean request time climbing while success rate still looks acceptable | Is latency increase broad or isolated to specific clusters? Are connect issues or upstream processing time driving the regression? |
| **Saturation** | How close proxy and upstream protective limits are to being hit | `downstream_cx_active`, `upstream_cx_active`, circuit-breaker open gauges, pending overflow, healthy membership ratios [S3][S5][S6] | Insufficient upstream capacity, bad retry policy, connection pool exhaustion, hot listener/cluster imbalance | Breaker open flags, overflow > 0, active connections pinned high with dropping healthy hosts | Is Envoy saturating before upstream fails completely? Which control limits are active right now? |

### Best-practice inference
- Treat **healthy host ratio** as the denominator for many other interpretations: rising load on shrinking healthy pools is worse than rising load on stable pools.
- For k8s operations, pair Envoy signal views with deployment/rollout context even when not directly emitted in Envoy metrics.
- Prefer section-level questions that separate **dependency failure** from **proxy exhaustion** because the first responder actions differ.
- Use a compact KPI wall in overview and preserve high-cardinality drilldowns for deep dive only.

## Telemetry sources

| Source type | How collected | What it provides | Pros | Cons | Common pitfalls |
|---|---|---|---|---|---|
| Envoy admin `/stats/prometheus` | Prometheus scrape from Envoy admin endpoint | Flattened `envoy_*` metric families with labels/tags | Direct, broad coverage of cluster/listener/http/server signals | Requires secure admin endpoint exposure and scrape hygiene | Mistaking missing optional families for zero traffic; admin endpoint access left too open [S1][S7] |
| Envoy admin `/stats` (text) | Direct pull of text counters/gauges/histograms | Canonical stat names (dot notation) and raw values | Closest to Envoy-native naming and semantics | Requires parser/transform layer for TSDB ingestion | Naming mismatch between dot stats and backend-normalized names [S1][S2] |
| Envoy Gateway prebuilt telemetry | Kubernetes deployment with Envoy Gateway and Prometheus/Grafana integration | Common cluster-level envoy metrics and queries | Faster onboarding for k8s teams | Focused on gateway use cases, not every sidecar/mesh variant | Assuming gateway metric presence in non-gateway Envoy topologies [S7] |
| AWS App Mesh Envoy telemetry | App Mesh control plane + Envoy proxy metrics | Practical metric names and semantic descriptions for envoy server/cluster/listener/http families | Useful operational interpretation and concrete names | App Mesh-specific framing may not match vanilla Envoy | Treating App Mesh-specific behavior as universal Envoy behavior [S8] |
| Control-plane and config metadata (xDS, k8s labels) | Enrichment in collector/pipeline into `context.*` | Service/team/env/namespace/cluster dimensions for filters and bounded group-by | Makes dashboards actionable by ownership and blast radius | Mapping conventions vary by pipeline | Unbounded labels (pod UID, request path) accidentally promoted to group-by [S11] |

### Optional features that change metrics
- Health-check and outlier subsystems can add/alter host-ejection and health-related stats. [S9][S12]
- Circuit-breaker metric families exist only when cluster circuit breakers are configured/enforced. [S6]
- Some downstream HTTP class metrics depend on HTTP connection manager presence and stat prefix configuration. [S4]

### What "no data" usually means
- `envoy_http_*` absent: HTTP connection manager stats may be disabled/not emitted for the target deployment mode.
- `envoy_cluster_circuit_breakers_*` absent: circuit breakers not configured or not exported by current pipeline.
- `envoy_cluster_membership_*` absent: service discovery/health-check integration not enabled or not exposed through tags.
- Broad `envoy_*` absence: scrape or ingestion outage, admin endpoint unreachable, or metric relabel/drop rules misconfigured.

### Best-practice inference
- In Kubernetes, treat scrape reachability and enrichment pipeline health as first-class telemetry dependencies; missing dimensions can be as damaging as missing metric families for dashboard usability.
- Start with cluster/listener/server core families, then expand to more granular HTTP/class/code splits only after confirming context fields and cardinality constraints.

## Log intelligence (Stage 4 handoff)

### Confirmed by sources

| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|---|---|---|---|---|
| Envoy access logs | Envoy proxy container logs (`stdout`) | Text line with quoted request, status, bytes, duration, user-agent, request-id, authority, upstream cluster | Unstructured text | Envoy default access log command operators and live Tsuga samples seen in Stage 4 (`context.log_name=envoy_access_log`) [S1][S2] |
| Envoy admin stats logs | Admin endpoint and telemetry stream | Mostly metric/stat outputs; not request access-line format | Structured-ish telemetry, not ideal for route parsing | Admin operations/statistics docs [S1][S2] |

Known format (confirmed):

```text
[2026-02-20T15:09:28.165Z] "GET / HTTP/1.1" 200 - 0 40 0 "fortio.org/fortio-1.67.1" "36836a5c-147c-9ad3-a9b0-0decd0a1e4d6" "10.96.195.207:5678" upstream_v1
```

Format hints:
- Timestamp is bracketed ISO8601 at line start.
- Request method/path/version is inside a quoted segment.
- Authority is quoted and may be `host:port` or host-only.
- Upstream cluster appears as final token.

Candidate query filters for Stage 4:
- Precise: `context.log_name:envoy_access_log AND context.service.name:envoy*`
  - Why: restricts to access-log stream plus envoy service naming.
  - Risk: may miss logs if service naming differs from `envoy*`.
- Fallback (broader): `context.service.name:envoy* OR container_name:/envoy`
  - Why: catches service-labeled and container-labeled envoy logs.
  - Risk: can include non-access envoy logs that need split handling.

Attribute mapping hints:

| Raw field | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| HTTP verb | `http.method` | High | Direct Grok extraction |
| HTTP path | `http.url` | High | Parse URL details later with `parse-attribute:url` |
| HTTP version | `http.version` | High | Stored under `http.*` for simplicity |
| Status code | `http.status_code` | High | Use numeric coercion and map-level for `level` |
| Duration | `http.latency` | High | Value is in ms in sample format |
| User agent | `http.useragent` | High | Optional secondary user-agent parser |
| Request id | `http.request_id` | High | Correlation-friendly key |
| Bytes in/out | `network.bytes_received` / `network.bytes_sent` | High | Numeric coercion required |
| Authority host/port | `network.destination.ip` / `network.destination.port` | Medium | Host-only variant needs alternate Grok rule |
| Response flags | `envoy.response_flags` | High | Keep raw flag token |
| Upstream cluster | `envoy.upstream_cluster` | High | Keep in envoy namespace |

### Best-practice inference
- Maintain two Grok rules for authority variants (`host:port` and host-only) to avoid parse drop.
- Keep `context.log_format=envoy` as required enrichment for filtering and rollout validation.

Parsing risks to account for in Stage 4:
- Variable authority token shape (`host:port` vs host-only).
- Potential dual formats if custom Envoy access-log template differs between environments.
- Quoted segments with spaces (user-agent) can break naive token-based patterns.
- Propagation delay after route update; verify with retries before declaring failure.

## Caveats and footguns

- **[errors-failures]** `upstream_rq_5xx` can rise from a single noisy cluster while global rate still looks normal. Always check cluster split before acting. (https://www.envoyproxy.io/docs/envoy/latest/configuration/upstream/cluster_manager/cluster_stats)
- **[errors-failures]** `upstream_rq_timeout` and `upstream_rq_5xx` often diverge; treating them as equivalent hides latency budget failures. (https://www.envoyproxy.io/docs/envoy/latest/configuration/upstream/cluster_manager/cluster_stats)
- **[latency-performance]** Mean latency from `rq_time_sum / rq_time_count` hides tail spikes; use it as trend indicator not SLA truth. (Inference)
- **[latency-performance]** If temporality is cumulative but widget uses `per-second`, derived latency math will drift. Stage 2 must confirm post-function. (Inference)
- **[traffic-volume]** `http.downstream_rq_total` and `cluster.upstream_rq_total` may represent different scopes; direct ratio can mislead without aligned filters. (https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_conn_man/stats)
- **[traffic-volume]** Request counters can spike during retries and shadow traffic making traffic growth look organic when it is policy-induced. (https://www.envoyproxy.io/docs/envoy/latest/configuration/upstream/cluster_manager/cluster_stats)
- **[saturation-capacity]** `*_pending_overflow` non-zero is already request loss not just warning pressure. (https://www.envoyproxy.io/docs/envoy/latest/configuration/upstream/cluster_manager/cluster_stats)
- **[saturation-capacity]** Circuit-breaker open gauges are binary-like states and should not be averaged over long windows. (https://www.envoyproxy.io/docs/envoy/latest/configuration/upstream/cluster_manager/cluster_circuit_breakers)
- **[saturation-capacity]** High active connections alone is not bad if healthy host pool scales with it. Check per-healthy-host ratio. (Inference)
- **[availability-health]** `membership_healthy` can fall due to health-check config issues not only backend outages. (https://www.envoyproxy.io/docs/envoy/latest/configuration/upstream/cluster_manager/cluster_hc)
- **[availability-health]** `server_live` confirms process liveness only and does not prove route-level correctness. (https://www.envoyproxy.io/docs/envoy/latest/operations/admin)
- **[resource-runtime]** Memory allocated and heap size can increase after config reloads or workload shifts without leak behavior. (Inference)
- **[resource-runtime]** `server.concurrency` is configuration state not runtime utilization; do not treat it as CPU saturation. (https://aws.github.io/aws-app-mesh-controller-for-k8s/reference/envoy_metrics/)
- **[errors-failures, saturation-capacity]** Retry amplification can both mask and worsen incidents by increasing upstream load during partial outages. (https://www.envoyproxy.io/docs/envoy/latest/configuration/upstream/cluster_manager/cluster_stats)
- **[traffic-volume, errors-failures]** `downstream_rq_4xx` can be client behavior noise and should not drive paging by itself. (https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_conn_man/stats)
- **[traffic-volume]** Listener names can be dynamic in some deployments causing cardinality blowups if used as unbounded group-by. (Inference)
- **[availability-health, saturation-capacity]** Cluster names from xDS may include ephemeral suffixes; enforce Top-N and avoid long-tail table widgets by default. (Inference)
- **[latency-performance]** Comparing latency across clusters with very different request size profiles can create false regressions. (Inference)
- **[errors-failures]** Client abort metrics may spike during client deploys and timeouts upstream may remain stable; do not misattribute immediately to backend. (https://www.envoyproxy.io/docs/envoy/latest/configuration/listeners/stats)
- **[availability-health]** Missing metrics may mean feature/path not enabled rather than true zero; use explicit missing-note language. (https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/observability/statistics)
- **[resource-runtime, traffic-volume]** Pod-level grouping in k8s can create churn noise during autoscaling and rollouts; prefer service or scope grouping first. (Inference)
- **[latency-performance, errors-failures]** Connect timeout and connect fail counters should be interpreted together; either one alone can understate network path issues. (https://www.envoyproxy.io/docs/envoy/latest/configuration/upstream/cluster_manager/cluster_stats)
- **[saturation-capacity]** Listener overflow and upstream pending overflow are different choke points; resolving one may not clear the other. (Inference)

## Confirmed Tsuga prefixes
- `envoy_*` — **CONFIRMED** (284 Envoy metrics discovered in Tsuga during Stage 2 over the 24h window ending 2026-02-16. After Stage 1b consolidation, 46 metrics are confirmed in the curated inventory and 8 legacy names are marked missing with explicit replacements.)

## Discovery status
Discovery: completed in Stage 2.
- `METRICS_FOUND`: 284 `envoy_*` metrics out of 788 total metrics in the catalog window.
- Key naming shape: response class metrics are exposed as `*_rq_xx` with `context.envoy_response_code_class` instead of dedicated `*_2xx/*_4xx/*_5xx` names.
- Filter convention: `context.envoy_response_code_class` values are numeric classes (`2`, `4`, `5`), not `2xx/4xx/5xx`.
- Key latency shape: request time is exposed as histogram `*_rq_time` rather than `*_time_sum/*_time_count` companion metrics.
- Context key shape in Tsuga uses underscores for Envoy tags (`context.envoy_cluster_name`, `context.envoy_listener_address`, `context.envoy_http_conn_manager_prefix`).
- Stage 1b consolidation is merged into primary artifacts and the promoted secondary metrics are now part of baseline integration scope.

## Top sources
1. https://www.envoyproxy.io/docs/envoy/latest/operations/admin
   Why: canonical documentation for `/stats` and `/stats/prometheus` interfaces.
2. https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/observability/statistics
   Why: Envoy statistics model and instrumentation semantics.
3. https://www.envoyproxy.io/docs/envoy/latest/configuration/upstream/cluster_manager/cluster_stats
   Why: primary source for cluster upstream request and connection metrics.
4. https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_conn_man/stats
   Why: primary source for HTTP downstream request families.
5. https://www.envoyproxy.io/docs/envoy/latest/configuration/listeners/stats
   Why: listener connection metrics and overflow semantics.
6. https://www.envoyproxy.io/docs/envoy/latest/configuration/upstream/cluster_manager/cluster_circuit_breakers
   Why: definitive breaker-open metrics and limit behavior.
7. https://www.envoyproxy.io/docs/envoy/latest/configuration/upstream/cluster_manager/cluster_hc
   Why: health-check behavior that drives healthy membership interpretation.
8. https://www.envoyproxy.io/docs/envoy/latest/configuration/observability/stats
   Why: stats tagging and dimension handling guidance for label/group-by design.
9. https://gateway.envoyproxy.io/latest/tasks/observability/proxy-metric/
   Why: k8s Envoy Gateway operational metric examples with concrete `envoy_*` names.
10. https://aws.github.io/aws-app-mesh-controller-for-k8s/reference/envoy_metrics/
    Why: practical Envoy metric naming and usage notes in production k8s meshes.
