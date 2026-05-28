# Istio Integration Context Bundle

## Metadata
**Technology:** Istio
**Deployment:** self-hosted
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** mixed
**Integration scope:** core service only
**Primary use-case:** reliability and performance

## How to use this bundle
- Use `01_istio_metrics.csv` as the source of truth for metric names, units, temporality assumptions, and safe query behavior.
- Use `02_istio_dashboard_plan.yaml` for the dashboard section layout, widgets, derived signals, explanation notes, triage chains, and playbooks.
- Use `03_istio_state.yaml` for machine-readable stage status, assumptions, and explicit unknowns that Stage 2 must verify.
- Use `04_istio_memory.md` for the human-readable handoff summary and tradeoffs made in Stage 1.
- Stage 2 will create `05_istio_metric_catalog.csv` as the discovered Tsuga metric catalog used for reconciliation and coverage checks.
- Stage 4 should read `## Log intelligence (Stage 4 handoff)` in this file and `03_istio_state.yaml` `log_intel` before creating log routes.

## What it is and what "good" looks like

### Confirmed by sources
- Istio is a service mesh that layers traffic management, security, and observability over application workloads, typically through Envoy sidecars or gateways in Kubernetes. [S1][S2][S3]
- Istio ships a standard set of service metrics for HTTP, gRPC, and TCP traffic, including request totals, duration histograms, byte histograms, gRPC message counters, and TCP connection and byte counters. [S1][S4][S5]
- Istio telemetry is shaped heavily by labels such as `reporter`, source and destination workload/service labels, canonical service labels, response code fields, and connection security policy. These dimensions make dashboards useful, but also create real cardinality risk. [S1][S4]
- Good mesh health means traffic is flowing, error rates are low, latency remains stable, mTLS posture matches policy, and no workload or namespace is disproportionately failing or saturating. [S1][S2][S6]
- Access logging is optional rather than universal. When enabled, Envoy access logs are emitted to standard output and can be collected from proxy containers. [S7]
- First-response dashboard routing for common incidents:
  - Upstream service failure or policy breakage: start in `errors-failures`.
  - Latency regression without obvious errors: start in `latency-performance`.
  - Mesh rollout, certificate, or peer-identity concern: start in `security-identity`.
- High-level paging intent for dashboards: surface user-visible request failures, identify whether blast radius is local or mesh-wide, and separate real dependency trouble from telemetry gaps or policy-induced drops. [S1][S6][S8]

### Best-practice inference
- For this integration, the most decision-useful surface is the data plane service telemetry (`istio_*`) rather than raw Envoy internals. Envoy internals are better handled by the separate Envoy integration when deeper proxy debugging is needed.
- Ambient mode, waypoint-specific behavior, and `istiod` control-plane health are important, but they should be treated as gated or follow-on coverage until Stage 2 confirms which metrics and context fields actually exist in Tsuga.
- The top three incident shapes likely to matter most in a general Istio dashboard are:
  1. **Destination service degradation**: request rate stays normal while 5xx or gRPC failures rise. Start in `errors-failures`.
  2. **Latency-led mesh degradation**: p95 duration rises before success rate collapses. Start in `latency-performance`.
  3. **Policy or identity regression**: mTLS mode flips, requests disappear, or one namespace loses traffic after rollout. Start in `security-identity`.

## Key concepts

### Glossary
| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| Service mesh | Infrastructure layer that handles service-to-service networking concerns | Changes in the mesh can impact many workloads at once | availability-health |
| Sidecar proxy | Envoy proxy injected next to an application pod | Source of most request-level telemetry in sidecar mode | traffic-volume |
| Gateway | Envoy-based ingress or egress entrypoint managed by Istio | Gateway failures can look mesh-wide even when backend apps are healthy | availability-health |
| Telemetry API | Istio API used to configure metrics, logs, and traces | Metric presence and labels can change through policy, not just code | security-identity |
| Reporter | Label indicating whether the metric came from source or destination perspective | Double counting risk if source and destination are mixed carelessly | traffic-volume |
| Canonical service | Stable workload identity used for service ownership views | Better grouping key than raw pod or revision labels during rollouts | traffic-volume |
| Canonical revision | Revision identity for a canonical service | Helps isolate bad rollouts without grouping by pod name | availability-health |
| Source workload | Workload originating a request | Useful for blaming noisy callers or bad client retries | traffic-volume |
| Destination workload | Workload receiving a request | Primary dimension for service health triage | errors-failures |
| Response code | HTTP response status | Fast first-pass view of failure classes | errors-failures |
| gRPC response status | gRPC-specific response classification | Needed when HTTP code alone is not enough | errors-failures |
| Connection security policy | Label showing whether the request used mTLS | Critical for validating mesh security posture and policy drift | security-identity |
| Request duration histogram | Histogram of request latency in milliseconds | Best base for p95 latency and tail-latency dashboards | latency-performance |
| Request bytes | Histogram of inbound request size | Helps explain large payload latency or resource pressure | traffic-volume |
| Response bytes | Histogram of outbound response size | Useful for spotting payload blowups and egress-heavy paths | traffic-volume |
| TCP reporting duration | Interval used for active TCP metric reporting | Low traffic TCP services can appear bursty or delayed | saturation-capacity |
| Workload identity | Combination of namespace, workload, service account, and policy identity | Identity drift often explains selective failures | security-identity |
| Peer exchange | Istio mechanism for sharing metadata across TCP connections | Missing metadata reduces dimension richness on TCP dashboards | security-identity |
| Namespace | Kubernetes tenancy and operational boundary | Safe first drilldown for ownership and blast radius | availability-health |
| Revision | Istio control-plane or workload revision marker | Useful for rollout correlation and canary validation | availability-health |
| mTLS | Mutual TLS between workloads | A posture change may be either expected hardening or accidental breakage | security-identity |
| Destination service | Service FQDN or logical destination label | Best high-level grouping key for service health | errors-failures |
| Source principal | Identity of the calling workload | Valuable for security investigations but sometimes absent | security-identity |
| Ambient mode | Istio dataplane mode without per-pod sidecars | Metric shapes and dimensions may differ from sidecar assumptions | availability-health |
| Waypoint proxy | Envoy proxy handling traffic for ambient workloads | Adds another ownership and routing layer to inspect | latency-performance |

[S1][S2][S3][S4][S5][S6][S7]

### Concept Map
```text
Client workload -> sends request to -> source Envoy proxy (why: source-side telemetry can record intent before destination handling)
Source Envoy proxy -> applies -> routing and policy decisions (why: retries, routing rules, and auth can change outcomes before app code)
Source Envoy proxy -> forwards to -> destination Envoy proxy or gateway (why: mesh hop where security and policy are enforced)
Destination Envoy proxy -> forwards to -> destination workload (why: last mesh hop before application handling)
Request -> increments -> istio_requests_total (why: baseline request traffic and denominator for many ratios)
Request -> contributes to -> istio_request_duration_milliseconds (why: tail latency is often the first user-visible symptom)
Request payload -> contributes to -> istio_request_bytes (why: larger payloads can explain latency and resource pressure)
Response payload -> contributes to -> istio_response_bytes (why: payload explosions can signal misuse or oversized responses)
gRPC call -> increments -> istio_request_messages_total and istio_response_messages_total (why: message-heavy paths can regress without HTTP error spikes)
TCP flow -> increments -> istio_tcp_connections_opened_total (why: connection churn exposes retry storms or connection instability)
TCP flow -> increments -> istio_tcp_connections_closed_total (why: close/open imbalance can reveal unhealthy churn)
TCP flow -> contributes to -> istio_tcp_sent_bytes_total and istio_tcp_received_bytes_total (why: non-HTTP traffic still needs throughput and saturation views)
Telemetry labels -> include -> reporter (why: source and destination perspectives must not be naively summed together)
Telemetry labels -> include -> source and destination workload/service fields (why: service ownership and blast radius depend on them)
Telemetry labels -> include -> canonical service labels (why: stable grouping during rollouts is more important than pod-level granularity)
Telemetry labels -> include -> connection_security_policy (why: mTLS posture is an operational and security signal)
Telemetry API -> can suppress or add -> metric tags (why: dashboards must gate on missing dimensions rather than assuming universal presence)
Access logging -> emits -> Envoy access logs to stdout when enabled (why: logs become the fastest evidence path for policy or routing failures)
Request failures -> first appear in -> response code and grpc status dimensions (why: classify app errors vs transport or policy errors quickly)
Rising latency -> often precedes -> rising errors (why: slow upstreams degrade before they fail hard)
Namespace ownership -> maps to -> context.team and service dimensions (why: triage should land with the right team quickly)
Control-plane rollout -> changes -> telemetry shape and mesh behavior (why: revision-aware views help distinguish rollout regressions from app regressions)
Ambient mode -> changes -> dataplane topology and labels (why: sidecar-era assumptions may not hold)
Gateway traffic -> can concentrate -> external user impact (why: ingress issues can look broader than single-service failures)
Missing telemetry -> may mean -> policy/config disabled metrics rather than healthy zero (why: absence is not evidence of health)
```

### Entities and dimensions
| Dimension | Why useful | Cardinality risk | Safe top-N suggestion |
|---|---|---|---|
| `context.env` | Environment split for prod vs non-prod | Low | 5 |
| `context.team` | Ownership boundary for triage | Low | 20 |
| `context.destination_service_namespace` | Best first-pass blast-radius grouping | Medium | 20 |
| `context.service.name` | Stable service filter if Tsuga enriches it | Medium | 20 |
| `context.destination_service` | Best destination health view | Medium | 20 |
| `context.destination_workload` | Useful for rollout or hot workload isolation | Medium | 15 |
| `context.source_workload` | Useful for noisy caller identification | Medium | 15 |
| `context.destination_canonical_service` | Safer grouping during revisions and rollouts | Medium | 15 |
| `context.source_canonical_service` | Safer caller grouping during revisions | Medium | 15 |
| `context.response_code` | Good for breakdowns, not dashboard filter default | Low | 10 |
| `context.grpc_response_status` | Required for gRPC-only triage | Low | 10 |
| `context.connection_security_policy` | Essential for security posture KPIs | Very low | 3 |
| `context.reporter` | Needed to prevent double counting | Very low | 2 |
| `context.k8s.cluster.name` | Multi-cluster view when present | Low | 10 |
| `context.k8s.pod.name` | Deep forensic drilldown only | High | 10 |
| `context.net.peer.ip` | Useful for security investigations only | Very high | do NOT group-by on dashboards |

**Do NOT group-by:** raw request path, pod UID, peer IP, source principal, or full destination FQDN without a bounded top-N and a strong reason. These are high-cardinality traps for mesh telemetry. [S1][S4][S6]

### Tsuga field mapping

### Confirmed by sources
The org-confirmed Tsuga context fields from `.env` are `context.env` and `context.team`.

### Confirmed in Tsuga (Stage 2 MCP discovery)
The live Istio metrics in Tsuga use plain keys such as `context.reporter`, `context.destination_service`, `context.destination_service_namespace`, `context.response_code`, `context.grpc_response_status`, and `context.connection_security_policy`, rather than the `context.istio.*` names originally inferred in Stage 1.

### Best-practice inference
| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| `reporter` | `context.reporter` | must-exist |
| `source_workload` | `context.source_workload` | optional |
| `source_workload_namespace` | `context.destination_service_namespace` or `context.source_workload_namespace` | optional |
| `source_canonical_service` | `context.source_canonical_service` | optional |
| `source_canonical_revision` | `context.source_canonical_revision` | optional |
| `destination_service` | `context.destination_service` | must-exist |
| `destination_service_namespace` | `context.destination_service_namespace` | optional |
| `destination_workload` | `context.destination_workload` | optional |
| `destination_workload_namespace` | `context.destination_workload_namespace` | optional |
| `destination_canonical_service` | `context.destination_canonical_service` | optional |
| `destination_canonical_revision` | `context.destination_canonical_revision` | optional |
| `response_code` | `context.response_code` | optional |
| `grpc_response_status` | `context.grpc_response_status` | optional |
| `connection_security_policy` | `context.connection_security_policy` | optional |
| `request_protocol` | `context.request_protocol` | optional |
| `source_principal` | `context.source_principal` | optional |
| `destination_principal` | `context.destination_principal` | optional |
| `source_cluster` | `context.k8s.cluster.name` or `context.source_cluster` | optional |
| `destination_cluster` | `context.destination_cluster` | optional |

## Golden signals

### Confirmed by sources
| Signal | What it means for Istio | Best telemetry | Typical causes when degraded | What people page on | Section questions |
|---|---|---|---|---|---|
| Traffic | Request and message flow across the mesh | `istio_requests_total`, `istio_request_messages_total`, `istio_response_messages_total`, size histograms [S1][S4][S5] | Traffic drains, route misconfig, gateway outage, partial namespace isolation | A service or namespace suddenly loses expected traffic or one destination dominates traffic unexpectedly | Is traffic present? Which destination services or namespaces changed most? |
| Errors | Failed HTTP/gRPC outcomes and abnormal service-path behavior | `istio_requests_total` with response labels and gRPC status labels [S1][S4][S5] | Upstream app failures, authz/authn policy breakage, TLS mismatch, retry storms | Sustained 5xx rise, gRPC failure concentration, one workload or namespace going red | Are failures broad or localized? Are they HTTP or gRPC led? |
| Latency | Time requests spend completing through the mesh | `istio_request_duration_milliseconds` [S1][S4] | Slow upstreams, oversized payloads, gateway bottlenecks, retry inflation | p95 or p99 latency rising across key services while throughput remains normal | Is tail latency broad or concentrated? Did payload size or protocol mix change? |
| Saturation | Pressure in connection churn, byte throughput, or heavy payload paths | TCP connection and byte counters plus request/response size histograms [S1][S4][S5] | Connection churn, large payloads, inefficient retries, long-lived TCP imbalance | Sudden churn, one service dominating mesh bytes, latency rising with stable request rate | Is one service over-consuming the mesh? Is connection churn preceding user-visible errors? |

### Best-practice inference
- Treat `reporter=destination` as the default surface for service health KPIs so request totals are not double counted.
- Use request-size and response-size trends as explanatory signals rather than primary paging KPIs.
- Security posture belongs adjacent to golden signals for Istio because a mesh can be "up" while identity or mTLS posture is silently wrong.

## Telemetry sources

### Confirmed by sources
| Source type | How collected | What it provides | Pros/cons | Common pitfalls |
|---|---|---|---|---|
| Istio standard service metrics | Exported from Istio-managed proxies and scraped by Prometheus-compatible systems | HTTP, gRPC, and TCP service telemetry with mesh labels | High operational value, standardized names; can still be label-heavy | Mixing source and destination reporters, assuming all labels exist everywhere [S1][S4] |
| Telemetry API overrides | Istio Telemetry resources change metric tags and providers | Metric/tag customization and selective telemetry shaping | Powerful for tailoring dashboards; makes metric shape mutable | Dashboards can silently break if tags are removed or renamed [S2][S6] |
| Prometheus addon / Prometheus scraping | Queries the scraped `istio_*` series | Ground truth examples for actual metric names and labels | Easiest way to verify names; common reference path | Scrape gaps or secure-scrape config issues look like missing service health [S8][S9] |
| Envoy access logs | Envoy proxy stdout when access logging is enabled | Per-request evidence for routing, status, latency, and policy debugging | Excellent incident evidence; complements metrics | Disabled by default in many deployments; mixed formats if customized [S7] |

### Best-practice inference
- "No data" for `istio_*` often means telemetry policy, scraping, or workload injection problems before it means healthy zero.
- gRPC message counters and some labels are protocol-specific; their absence can be expected on non-gRPC traffic.
- Ambient-mode deployments may expose different operational pivot points than sidecar mode, so Stage 2 should verify which dimensions actually appear in Tsuga.

## Log intelligence (Stage 4 handoff)

### Confirmed by sources

| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|---|---|---|---|---|
| Sidecar or gateway Envoy access logs | Proxy container stdout via `kubectl logs` or centralized log collection | Envoy text access log line | Unstructured text by default | Istio access-log task says Envoy proxies print access information to standard output and shows the default format [S7] |
| Customized Envoy access logs | Telemetry API or mesh config | Custom text or JSON depending on operator configuration | Structured or unstructured | Istio access-log task documents Telemetry API and MeshConfig based customization [S7] |

Known log formats:
- **Envoy default access log**
  - Sample line: `[2020-04-03T04:57:50.690Z] "GET /productpage HTTP/1.1" 200 - "-" "-" 0 612 90 89 "10.244.0.8" "curl/7.64.1" "6fcb..." "productpage:9080" "127.0.0.1:9080" outbound|9080||productpage.default.svc.cluster.local 127.0.0.1:57620 10.96.55.58:9080 10.244.0.11:9080 inbound|9080|| 10.244.0.11:41890 10.244.0.11:9080 10.244.0.8:0 outbound_.9080_._.productpage.default.svc.cluster.local default`
  - Delimiter and shape notes: whitespace-delimited line with quoted request and user-agent fields, then upstream cluster and address tokens.
  - Timestamp pattern: bracketed ISO-8601 at line start.
  - Quoting behavior: request line, referer, user agent, request id, authority, and upstream host fields are quoted.
  - Optional fields: response flags, route name, and cluster tokens vary by configuration.

Candidate query filters for Stage 4:
- Precise: `context.service.name:istio-proxy AND context.log_name:access`
  - Rationale: likely to isolate centralized access logs if the collector preserves service and log stream names.
  - Risk: may miss logs if the org uses a different `context.service.name` mapping.
- Fallback: `message:\"HTTP/1.\" AND (message:\"outbound|\" OR message:\"inbound|\")`
  - Rationale: catches default Envoy access-log lines even when enrichment is sparse.
  - Risk: text-shape filter can match non-Istio Envoy logs or partially customized formats.

Attribute mapping hints:

| Raw field | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| timestamp | `timestamp` | High | Parse bracketed ISO timestamp directly |
| method | `http.method` | High | Taken from quoted request segment |
| path | `http.url` | High | Preserve raw path first; URL parsing can happen later |
| protocol | `http.version` | High | Usually `HTTP/1.1` or `HTTP/2` |
| status | `http.status_code` | High | Numeric coercion required |
| duration | `http.latency` | Medium | Verify unit in emitted format before normalization |
| request id | `http.request_id` | Medium | Present in default format but may be empty |
| authority | `server.address` | Medium | Quoted authority can be host or host:port |
| upstream cluster | `istio.upstream_cluster` | High | Useful for route and service attribution |
| response flags | `envoy.response_flags` | High | Keep raw flags rather than over-normalizing |

Parsing risks:
- Customized Telemetry API access-log formats can invalidate default-token Grok patterns.
- Envoy default format contains quoted segments and bare tokens intermixed, so naive split-on-space parsing breaks.
- Some deployments emit JSON access logs instead of text.
- Duration unit is easy to mis-assume; Stage 4 should verify against current format before setting a normalizer.
- Ingress and sidecar access logs may share shape but differ operationally.

### Best-practice inference
- If logs are centralized with Kubernetes enrichment, expect namespace and pod dimensions to be easier to rely on than Istio-specific semantic keys.
- Keep a fallback parser path for host-only vs host:port authority tokens.
- Treat access logs as optional evidence, not guaranteed coverage.

## Caveats and footguns
- **[traffic-volume]** Do not sum source and destination reporters together for the same KPI. Pick one default reporter, usually destination, or the dashboard will double count. [S1][S4]
- **[errors-failures]** `istio_requests_total` can show failures caused by policy, upstream app errors, or gateway problems; response code alone is not enough for blame. [S1][S6]
- **[latency-performance]** `istio_request_duration_milliseconds` is a histogram. Use percentiles or carefully chosen summary views, not naive arithmetic across percentiles. [S1]
- **[latency-performance]** Request duration unit is milliseconds, not seconds. Normalizer mistakes can silently produce misleading charts. [S1]
- **[traffic-volume, saturation-capacity]** Request and response byte histograms explain payload shape, but they are not always the best primary "throughput" KPI. [S1][S4]
- **[security-identity]** `connection_security_policy` can be absent if telemetry customization removed it or if the integration path does not preserve the label. (Inference)
- **[security-identity]** A drop in mTLS-labeled traffic can be either a regression or an intentional plaintext exception. Pair security dashboards with current policy context. (Inference)
- **[availability-health]** Missing mesh metrics may indicate workloads are not injected or not scraped, not that the service is healthy. [S8][S9]
- **[availability-health]** Gateway-heavy traffic can dominate user-visible behavior; service-level dashboards can look healthy while ingress is broken. (Inference)
- **[traffic-volume]** `source_workload` and `destination_workload` are useful but can churn during rollouts; canonical service is usually safer for high-level comparisons. [S4]
- **[traffic-volume, errors-failures]** Full destination service FQDNs can be noisy in legends. Prefer canonical service or shorter service labels when available. (Inference)
- **[errors-failures]** gRPC failures may not map cleanly to HTTP 5xx expectations. Keep a grpc-status breakdown when the protocol mix is meaningful. [S1][S4]
- **[saturation-capacity]** TCP metrics are reported on a timer for active connections and at connection end, so low-volume services can look jagged. [S5]
- **[saturation-capacity]** Opened vs closed TCP connections over a short window is a churn indicator, not a literal concurrency gauge. (Inference)
- **[latency-performance, saturation-capacity]** Large request or response sizes can drive latency without error spikes. Keep payload views near latency widgets. (Inference)
- **[availability-health, security-identity]** Telemetry API changes can remove labels that dashboards depend on without changing metric names. [S2][S6]
- **[security-identity]** Ambient mode and waypoint proxies may change the practical meaning of sidecar-era ownership fields. (Inference)
- **[availability-health]** `reporter` is low cardinality and safe; pod names and principals are not. Avoid pod-level timeseries in the overview. (Inference)
- **[errors-failures, traffic-volume]** Query-value widgets should stay aggregated and ungroupped. Use top-lists for "who is impacted" instead of forcing QV semantics. (Inference from Tsuga rules)
- **[traffic-volume, errors-failures, latency-performance]** If the org normalizes Prometheus names to dotted Tsuga names in Stage 2, patch all references consistently; partial renames will break formulas. (Inference)
- **[availability-health, security-identity]** Access logs may be disabled even when metrics work. Stage 4 must not assume logs exist just because metrics do. [S7]

## Confirmed Tsuga prefixes
- `istio_*` — **CONFIRMED** (7 live metrics found in Tsuga via MCP on April 2, 2026: `istio_build`, request, duration, size, and gRPC message families)
- `pilot_*` — **CONFIRMED** (28 live metrics found in Tsuga via MCP on April 2, 2026; control-plane coverage is real and can support secondary diagnostics)

## Discovery status
- Discovery: completed in Stage 2 via Tsuga MCP plus catalog bootstrap.
- Confirmed live `istio_*` metrics: `istio_build`, `istio_requests_total`, `istio_request_duration_milliseconds`, `istio_request_bytes`, `istio_response_bytes`, `istio_request_messages_total`, `istio_response_messages_total`.
- Confirmed live `pilot_*` metrics: 28, including push, convergence, queue, endpoint-readiness, and routing-conflict families.
- Notable gap: the documented Istio TCP metric families are not currently present in Tsuga, so the Stage 2 baseline was re-centered on request-path and pilot control-plane metrics.

## Top sources
- [S1] https://istio.io/latest/docs/reference/config/metrics/ — canonical list of Istio standard metrics and label semantics.
- [S2] https://istio.io/latest/docs/reference/config/telemetry/ — Telemetry API reference explaining how metrics and logs can be altered.
- [S3] https://istio.io/latest/docs/overview/what-is-istio/ — concise product-level explanation of Istio’s operational role.
- [S4] https://istio.io/latest/docs/tasks/observability/metrics/querying-metrics/ — shows real Prometheus queries and example `istio_requests_total` usage.
- [S5] https://istio.io/latest/docs/tasks/observability/metrics/tcp-metrics/ — confirms TCP metric names and reporting behavior.
- [S6] https://istio.io/latest/docs/tasks/observability/metrics/customize-metrics/ — confirms that operators can alter metric shape and labels.
- [S7] https://istio.io/latest/docs/tasks/observability/logs/access-log/ — canonical Istio access-log behavior and default format guidance.
- [S8] https://istio.io/latest/docs/tasks/observability/metrics/ — observability task index anchoring the supported metrics workflows.
- [S9] https://istio.io/latest/docs/tasks/observability/metrics/secure-metrics/ — secure scraping path and reasons mesh metrics can disappear operationally.
- [S10] https://istio.io/latest/docs/ops/deployment/performance-and-scalability/ — deployment-level performance guidance used to shape saturation and blast-radius assumptions.
