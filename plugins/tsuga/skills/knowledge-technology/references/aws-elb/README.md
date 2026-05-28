# AWS ELB Integration Context Bundle

## Metadata
**Technology:** AWS ELB - Network ELB (NLB) surface
**Deployment:** managed
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** mixed
**Integration scope:** core service only
**Primary use-case:** reliability and performance

## How to use this bundle
Read `01_aws-elb_metrics.csv` first for the metric source of truth and the current Stage 1 assumptions about NLB metric names, units, and safe math. Read `02_aws-elb_dashboard_plan.yaml` next for the dashboard sections, widgets, derived signals, explanation notes, triage chains, and playbooks.

Use `03_aws-elb_state.yaml` for machine-readable unknowns, assumptions, and log intelligence handoff. Use `04_aws-elb_memory.md` for the narrative summary of what Stage 2 should verify first. Stage 2 will create `05_aws-elb_metric_catalog.csv` as the discovered Tsuga metric catalog for reconciliation and coverage checks. Stage 4 should read this file's `Log intelligence (Stage 4 handoff)` section and `03_aws-elb_state.yaml` `log_intel` block before attempting route creation.

## What it is and what "good" looks like
### Confirmed by sources
AWS Network Load Balancer is a layer-4 load balancer that forwards TCP, TLS, UDP, TCP_UDP, QUIC, and TCP_QUIC traffic to target groups while preserving source IP and supporting zonal load-balancer nodes. It is designed for very high connection rates, long-lived connections, and low-latency forwarding across enabled Availability Zones. Good NLB posture means new-flow demand is absorbed without rising rejected flows, reset rates stay near baseline, healthy targets remain available in every enabled zone, and capacity-unit consumption grows proportionally with traffic rather than spiking from inefficient connection patterns. AWS documents that NLB metrics are emitted in 60-second CloudWatch intervals when traffic exists, and that some metrics are absent when there is no traffic rather than explicitly reporting zero. [CloudWatch metrics](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-metrics.html), [NLB overview](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/introduction.html), [How ELB works](https://docs.aws.amazon.com/elasticloadbalancing/latest/userguide/how-elastic-load-balancing-works.html)

At incident time, the first question is whether the NLB is accepting and forwarding connections. The next question is whether failures originate at the load balancer edge, the target fleet, or a zonal health problem. The third question is whether capacity pressure is coming from connection churn, bytes transferred, active flows, or port allocation. Incident shape 1 is flow rejection or connection establishment failure during burst load; start in `nlb-failures-resets`. Incident shape 2 is rising resets with healthy-host erosion; start in `nlb-target-health`. Incident shape 3 is cost or headroom drift without an outright outage; start in `nlb-capacity-efficiency`.

### Best-practice inference
For NLB-heavy systems, resets and rejected flows usually tell operators more than absolute traffic counts because they represent direct connection failure instead of normal demand. A healthy dashboard should let an on-call engineer distinguish three patterns quickly: traffic surge with sufficient headroom, traffic surge with capacity rejection, and target instability masked as a network symptom.

If the environment uses mixed protocols, protocol-specific breakdowns become valuable only after the main health view is stable. For first-response dashboards, it is better to lead with all-flow metrics and keep protocol-split metrics as deep-dive diagnostics because protocol cardinality is lower than per-target or per-client dimensions but still increases visual noise.

## Key concepts
### Glossary
| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| Network Load Balancer | AWS managed layer-4 load balancer | Primary ingress or east-west TCP/TLS/UDP traffic control plane | nlb-demand-throughput |
| Listener | Protocol and port definition that accepts client connections | Traffic shape depends on listener protocol mix | nlb-demand-throughput |
| Target group | Set of registered backend targets | Failures often localize by target group before the whole NLB degrades | nlb-target-health |
| Load balancer node | Per-AZ node created for an enabled subnet/AZ | Zonal problems often appear before whole-balancer issues | nlb-target-health |
| Availability Zone | Isolated AWS zone hosting NLB nodes and targets | Blast radius and failover analysis depend on AZ splits | nlb-target-health |
| NewFlowCount | Number of new client-to-target flows | Best traffic denominator for rejection and reset ratios | nlb-demand-throughput |
| ActiveFlowCount | Concurrent active flows | Tracks occupancy and long-lived connection pressure | nlb-capacity-efficiency |
| ProcessedBytes | Total bytes processed by the NLB | Throughput and bytes-per-flow context | nlb-demand-throughput |
| PeakBytesPerSecond | Period burst throughput gauge | Detects short spikes hidden by average byte rates | nlb-capacity-efficiency |
| PeakPacketsPerSecond | Period burst packet-rate gauge | Surfaces packet-heavy workloads and small-packet storms | nlb-capacity-efficiency |
| RejectedFlowCount | Connections rejected by the load balancer | Direct customer-impact signal | nlb-failures-resets |
| PortAllocationErrorCount | Backend port allocation failures | Strong indicator of saturation or ephemeral-port pressure | nlb-failures-resets |
| TCP_Target_Reset_Count | TCP resets from targets | Backend instability, health, or protocol mismatch symptom | nlb-failures-resets |
| TCP_ELB_Reset_Count | TCP resets initiated by the load balancer | Edge-side timeout or lifecycle symptom | nlb-failures-resets |
| TCP_Client_Reset_Count | TCP resets initiated by clients | Client churn or upstream timeout symptom | nlb-failures-resets |
| HealthyHostCount | Healthy registered targets | Available serving capacity denominator | nlb-target-health |
| UnHealthyHostCount | Unhealthy registered targets | Capacity erosion and failover risk | nlb-target-health |
| ZonalHealthStatus | Zone-level health signal | AZ degradation and DNS failover context | nlb-target-health |
| ClientTLSNegotiationErrorCount | Failed TLS negotiations at the client edge | TLS-specific ingress failures that do not always show as target issues | nlb-failures-resets |
| SecurityGroupBlockedFlowCount | TLS flows blocked by NLB security groups | Security policy rejection that does not equal target unhealthiness | nlb-failures-resets |
| Cross-zone load balancing | NLB feature that lets nodes send traffic to targets in all enabled AZs | Changes how zonal imbalance should be interpreted | nlb-target-health |
| Passive health checks | Unconfigurable NLB behavior that observes target response quality | Backend instability can surface before active health checks mark targets unhealthy | nlb-target-health |
| Fail open | NLB behavior when all targets fail health checks or a target group is empty | Healthy-host metrics alone can mislead during total-failure scenarios | nlb-target-health |
| NLCU | Network Load Balancer capacity unit | Capacity and cost pressure roll up to whichever dimension dominates the hour | nlb-capacity-efficiency |

### Concept Map
Client -> connects to -> NLB listener (why: every incident begins with whether the listener accepted work)
Listener -> forwards to -> target group (why: target-group health determines forwarding safety)
Target group -> contains -> targets (why: host health erosion reduces serving capacity)
Enabled Availability Zone -> hosts -> NLB node (why: zonal failure can remove an IP from DNS)
NLB node -> forwards to -> healthy targets in its zone by default (why: zonal imbalance matters even without a full outage)
Cross-zone load balancing -> widens routing set to -> healthy targets in all enabled zones (why: cross-zone changes how AZ-local symptoms appear)
NewFlowCount -> measures -> demand churn (why: best denominator for rejection and reset ratios)
ActiveFlowCount -> measures -> connection occupancy (why: long-lived flows consume headroom differently than burst traffic)
ProcessedBytes -> captures -> total transferred bytes (why: byte-heavy traffic can dominate NLCU cost)
PeakBytesPerSecond -> highlights -> burst throughput (why: short spikes can be hidden in totals)
PeakPacketsPerSecond -> highlights -> packet intensity (why: small-packet floods stress networking differently than large transfers)
RejectedFlowCount -> indicates -> direct connection denial (why: user impact starts before target-side investigation)
PortAllocationErrorCount -> indicates -> backend port exhaustion pressure (why: strong clue for capacity bottlenecks)
TCP_Target_Reset_Count -> points to -> target-side connection termination (why: target instability and protocol mismatch show here)
TCP_ELB_Reset_Count -> points to -> load-balancer-side connection termination (why: edge lifecycle and timeout behavior show here)
TCP_Client_Reset_Count -> points to -> client-side aborts (why: not all resets indicate backend failure)
HealthyHostCount -> bounds -> available serving pool (why: low healthy capacity magnifies rejection and reset risk)
UnHealthyHostCount -> amplifies -> routing instability (why: degraded fleets often precede customer-visible failures)
ZonalHealthStatus -> summarizes -> per-AZ health posture (why: useful for DNS failover and zonal isolation)
Passive health checks -> detect -> target problems earlier than active checks (why: resets can rise before unhealthy counts do)
Fail open -> routes to -> all targets when all are unhealthy (why: traffic can continue while health counters look alarming)
SecurityGroupBlockedFlowCount -> separates -> policy blocks from target failures (why: remediation differs from health-based outages)
ClientTLSNegotiationErrorCount -> separates -> TLS edge failures from target health issues (why: cert/policy problems look different from app outages)
NLCU -> is dominated by -> highest of new flows, active flows, or processed bytes (why: capacity and cost diagnostics need all three dimensions)
Load balancer identity -> maps to -> context.loadbalancer (why: ownership and blast radius require a stable primary grouping key)
Target group identity -> maps to -> context.targetgroup (why: backend isolation needs a second-level grouping key)
Availability Zone -> maps to -> context.availabilityzone (why: zonal impairment must be surfaced explicitly)
Environment and team tags -> map to -> context.env and context.team (why: dashboards need multi-tenant filtering and routing context)

### Entities and dimensions
| Entity/Dimension | Why useful | Cardinality risk | Safe top-N suggestion | Do NOT group-by guidance |
|---|---|---|---|---|
| `context.loadbalancer` | Primary NLB ownership and blast-radius key | Low | 20 | Use as first grouping before any target details |
| `context.targetgroup` | Localizes unhealthy hosts and reset-heavy backends | Medium | 20 | Avoid combining with ephemeral or client identifiers |
| `context.availabilityzone` | Detects zonal impairment and failover asymmetry | Low | 6 | Do not interpret alone without load balancer context |
| `context.cloud.region` | Separates regional fleets | Low | 10 | Prefer as a global filter in single-region dashboards |
| `context.cloud.account.id` | Splits multi-account NLB estates | Low | 10 | Better as a global filter than a chart series |
| `context.env` | Distinguishes prod, staging, and test | Low | 5 | Use as dashboard filter, not chart group-by |
| `context.team` | Ownership and routing | Low | 10 | Keep as filter, not a timeseries split |
| `context.listener` | Protocol-port isolation for listener-specific incidents | Medium | 10 | Do not put on overview charts by default |
| `context.protocol` | Distinguishes TCP/TLS/UDP style behavior | Medium | 10 | Use only when the NLB actually mixes protocols |
| `context.target.ip` | Helpful for deep host isolation | High | 15 | Never use on overview; only use in deep-dive top lists if verified |
| `context.target.port` | Distinguishes shared-target services | High | 10 | Avoid unless troubleshooting a specific port mapping problem |
| `context.security_group` | Useful for policy-block diagnosis | Medium | 10 | Only use when security-group-blocked metrics are confirmed |
| `context.scope.name` | Fallback generic workload identity | Medium | 20 | Use only if `context.loadbalancer` is absent in Stage 2 discovery |

### Tsuga field mapping
#### Confirmed by sources
| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| LoadBalancer | `context.loadbalancer` | Must-exist |
| TargetGroup | `context.targetgroup` | Strongly preferred |
| AvailabilityZone | `context.availabilityzone` | Strongly preferred |
| AWS Region | `context.cloud.region` | Optional |
| AWS Account ID | `context.cloud.account.id` | Optional |
| Environment tag | `context.env` | Must-exist |
| Team tag | `context.team` | Must-exist |
| Listener ARN or port/protocol metadata | `context.listener` | Optional |
| Protocol | `context.protocol` | Optional |

AWS documents `LoadBalancer`, `AvailabilityZone`, and `TargetGroup` as dimensions on multiple NLB metrics, so these are the strongest expected Tsuga mappings for grouping and filters. [CloudWatch metrics](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-metrics.html)

#### Best-practice inference
If a CloudWatch-to-Tsuga pipeline normalizes dimension names differently, `context.scope.name` is the safest fallback for the primary identity field until Stage 2 confirms the real attribute set. Listener, target IP, target port, and security-group fields are useful only if the ingestion pipeline preserves them consistently enough for bounded groupings.

## Golden signals
### Confirmed by sources
| Signal | What it means for NLB | Typical causes when it degrades | Best telemetry sources | What people page on | Section questions |
|---|---|---|---|---|---|
| Traffic | Connection and byte demand through the NLB | burst connection churn, sudden demand drops, packet floods | `NewFlowCount`, `ActiveFlowCount`, `ProcessedBytes`, `PeakBytesPerSecond`, `PeakPacketsPerSecond` | demand collapse, unexpected surge, unplanned traffic shape shift | Is the NLB receiving expected flow demand? Are bursts changing throughput shape? |
| Errors | Connection acceptance and reset failures | target instability, port exhaustion, TLS negotiation failures, policy blocks | `RejectedFlowCount`, reset counters, `PortAllocationErrorCount`, TLS/security-group metrics | rejected flow spikes, sustained reset growth | Are failures edge-side, target-side, or client-side? |
| Latency | NLB itself is low-latency, so latency proxies come from resets, churn, and target health rather than an app-layer response-time metric | overloaded backends, SYN/backlog pressure, TLS negotiation issues | reset counters, `ActiveFlowCount`, `HealthyHostCount`, logs | connection establishment delay, connection timeouts, rising resets during stable demand | Is there connection instability even if raw traffic looks normal? |
| Saturation | Headroom consumed by flows, bytes, and available healthy targets | port allocation pressure, active-flow buildup, uneven zonal capacity, byte-heavy workloads | `ConsumedLCUs`, `PortAllocationErrorCount`, `ActiveFlowCount`, healthy/unhealthy host counts | rejection with capacity pressure, cost/headroom drift, zonal exhaustion | Do we still have safe serving headroom? Which capacity dimension is binding? |

### Best-practice inference
For NLBs, latency is rarely a first-class single metric the way it is for ALBs. Operators usually infer user-visible latency trouble from a combination of connection resets, host health, and rising connection occupancy. A practical dashboard should therefore emphasize failure ratios and capacity efficiency over a synthetic latency number that the platform does not emit directly.

## Telemetry sources
### Confirmed by sources
| Source type | How collected | What it provides | Pros/cons | Common pitfalls |
|---|---|---|---|---|
| CloudWatch NLB metrics | AWS publishes 60-second metrics when traffic exists | Canonical NLB flow, reset, host-health, and capacity metrics | Best source for baseline health; no app-layer payload context | No traffic often means no datapoints, not explicit zero; security-group rejections are not captured for all paths |
| NLB access logs to S3 | Optional access logging, legacy path | TLS connection details and log-line level triage data | High forensic value for TLS listeners | Disabled by default; TLS-only; eventual consistency; best-effort delivery |
| NLB logs to CloudWatch Logs/Data Firehose/S3 | Enhanced logging pipeline | Centralized log delivery with more flexible sinks | Better operational routing than legacy S3-only flow | Still optional; format and field choices must be verified in environment |
| Target health APIs and console state | AWS target group health state and reason codes | Registration, unhealthy, draining, unavailable reasons | Explains host-count drops | Separate from metric stream; not a metric source by itself |
| Pricing and capacity references | AWS pricing and capacity reservation docs | Meaning of LCUs and throughput conversions | Grounds capacity-efficiency widgets | Not operational telemetry; use for interpretation only |

NLB metrics are reported only while requests are flowing, access logs are optional and TLS-listener scoped, and target health APIs expose reason codes such as failed health checks or deregistration progress. [CloudWatch metrics](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-metrics.html), [Access logs](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-access-logs.html), [CloudWatch logs](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-logs.html), [Check target health](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/check-target-health.html)

### Best-practice inference
If there is no data for `HealthyHostCount` or `UnHealthyHostCount`, the meaning is ambiguous until Stage 2 confirms the ingestion model: it can mean no registered targets in scope, no traffic-driven metric emission in the selected window, or an ingestion gap. Dashboards should therefore use missing-note language instead of treating null as healthy.

## Log intelligence (Stage 4 handoff)
### Confirmed by sources
1. Log sources matrix

| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|---|---|---|---|---|
| Legacy NLB access logs | S3 bucket objects under `AWSLogs/.../elasticloadbalancing/.../net.<load-balancer-id>...log.gz` | Space-delimited log entries | Semi-structured text | [Access logs](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-access-logs.html) |
| Enhanced NLB logs | CloudWatch Logs, Data Firehose, or S3 | AWS-managed delivered log records, optionally Parquet in some sinks | Structured delivery path, exact payload to verify | [CloudWatch logs](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-logs.html) |

2. Known log formats

- `NLB legacy TLS access log`
  - Sample line: `tls 2.0 2024-01-01T00:00:00.000000Z net/my-nlb/1234567890abcdef 192.0.2.10:44321 198.51.100.20:443 0.000 0.002 0.000 200 200 0 57 "TLSv1.2" "ECDHE-RSA-AES128-GCM-SHA256" ...`
  - Delimiter and shape notes: space-delimited fields with quoted string fields later in the record; field count can evolve over time.
  - Timestamp pattern: ISO-8601 UTC with microseconds.
  - Quoting behavior: some string fields are double-quoted.
  - Optional fields: AWS notes that parsers should stop at the last documented field and tolerate trailing additions. [Access logs](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-access-logs.html)

3. Candidate query filters for Stage 4

- Precise: `context.service.name:"aws-networkelb" AND (context.loadbalancer:* OR context.targetgroup:*)`
  - Rationale: narrows to logs already normalized as NLB traffic while keeping the two most useful identity keys.
  - Risk: depends on Stage 4 confirming the service-name mapping in the current pipeline.
- Fallback: `"elasticloadbalancing" AND "net/" AND ("TLS" OR "tcp")`
  - Rationale: catches raw AWS-delivered NLB log lines when structured enrichment is weak.
  - Risk: can overmatch adjacent ELB log sources and may miss non-TLS paths.

4. Attribute mapping hints

| Raw field | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| load balancer id | `context.loadbalancer` | High | Should map from `net/<lb-name>/<id>` path segment |
| client ip:port | `context.client.address` / `context.client.port` | Medium | Split required |
| target ip:port | `context.target.address` / `context.target.port` | Medium | Split required |
| tls protocol | `context.tls.version` | Medium | Legacy logs are TLS-listener scoped |
| tls cipher | `context.tls.cipher` | Medium | Useful for negotiation-error triage |
| elb status / connection outcome | `context.status` | Medium | Exact field naming depends on sink format |
| bytes received/sent | `context.network.bytes_in` / `context.network.bytes_out` | Low | Verify field names in actual environment |

5. Parsing risks

- Legacy access logs are TLS-listener only, so absence of logs can mean feature not enabled rather than no traffic.
- Delivery is eventually consistent and best effort, so log counts should not be used as an authoritative traffic ledger.
- Sample-field schemas may evolve; AWS recommends parsers tolerate appended fields.
- Mixed raw and enriched delivery formats are possible if S3 legacy logging and CloudWatch Logs are both enabled.
- Target and client endpoint fields require splitting host and port safely.

### Best-practice inference
If the environment uses enhanced CloudWatch Logs delivery, Stage 4 should prefer the actual delivered schema over the legacy text format even when both are enabled. If only metric telemetry is present and no logs are configured, Stage 4 should route through target health reason codes and infrastructure events rather than fabricating an NLB log route.

## Caveats and footguns
- **[nlb-demand-throughput]** NLB metrics are emitted only when requests are flowing, so missing points can mean idle traffic rather than telemetry failure. ([CloudWatch metrics](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-metrics.html))
- **[nlb-demand-throughput]** For Network Load Balancers with security groups, traffic rejected by the security groups is not captured in the standard CloudWatch metrics discussed on the metrics page. ([CloudWatch metrics](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-metrics.html))
- **[nlb-demand-throughput]** `ProcessedBytes` and `PeakBytesPerSecond` can rise because of payload growth even when connection counts remain flat. (Inference)
- **[nlb-demand-throughput]** Packet-heavy small-payload traffic can make `PeakPacketsPerSecond` more informative than bytes. (Inference)
- **[nlb-failures-resets]** `RejectedFlowCount` is direct customer impact; do not average it away as a background signal. ([CloudWatch metrics](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-metrics.html))
- **[nlb-failures-resets]** `TCP_Target_Reset_Count` and `TCP_ELB_Reset_Count` indicate different ownership domains and should not be collapsed into one root-cause KPI. ([CloudWatch metrics](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-metrics.html))
- **[nlb-failures-resets]** `TCP_Client_Reset_Count` can spike during client-side timeout or retry storms; it does not prove the NLB or target is unhealthy. ([CloudWatch metrics](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-metrics.html))
- **[nlb-failures-resets]** Port allocation errors usually indicate urgent backend flow-capacity problems and should be triaged alongside rejected flows. ([Troubleshooting](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-troubleshooting.html))
- **[nlb-failures-resets]** TLS negotiation failures belong with edge failure analysis, not target-health analysis. ([CloudWatch metrics](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-metrics.html))
- **[nlb-failures-resets]** Security-group-blocked flow metrics are TLS/security-group specific and may be absent entirely in otherwise healthy environments. (Inference)
- **[nlb-target-health]** Healthy-host counts should be interpreted by target group and AZ, not only as a global sum. ([CloudWatch metrics](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-metrics.html))
- **[nlb-target-health]** Passive health checks cannot be directly monitored, so reset spikes can lead host-count changes. ([Health checks](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/target-group-health-checks.html))
- **[nlb-target-health]** If all targets fail health checks at once, NLB can fail open, so traffic may still flow while health looks bad. ([Health checks](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/target-group-health-checks.html))
- **[nlb-target-health]** If a zone has no healthy targets, AWS can remove that zone's NLB IP from DNS, which changes client routing patterns quickly. ([Health checks](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/target-group-health-checks.html))
- **[nlb-target-health]** HTTP or HTTPS health checks use the load balancer node IP and listener port in the host header, which can surprise backends that expect a virtual host. ([Health checks](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/target-group-health-checks.html))
- **[nlb-target-health]** UDP and QUIC services often rely on non-UDP health checks, so health semantics can diverge from the served protocol. ([Health checks](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/target-group-health-checks.html))
- **[nlb-capacity-efficiency]** NLCU cost and pressure are driven by the highest of new flows, active flows, or processed bytes for the hour, not the sum of those dimensions. ([ELB FAQ](https://aws.amazon.com/th/elasticloadbalancing/faqs/))
- **[nlb-capacity-efficiency]** `ConsumedLCUs` is capacity context, not a direct outage indicator; it becomes actionable when paired with rejection, reset, or host-health deterioration. (Inference)
- **[nlb-capacity-efficiency]** Active-flow growth can be healthy for long-lived connections; interpret it with new-flow churn and resets before calling it saturation. (Inference)
- **[nlb-capacity-efficiency]** Protocol-specific flow metrics (`ActiveFlowCount_TCP`, `_TLS`, `_UDP`) are diagnostic enrichments and can clutter overview panels if used without a protocol filter. (Inference)
- **[nlb-capacity-efficiency]** Target quotas and listener quotas can become design constraints before metrics obviously fail, so persistent headroom widgets need an accompanying note rather than a hard threshold. ([NLB quotas](https://docs.aws.amazon.com/en_us/elasticloadbalancing/latest/network/load-balancer-limits.html))

## Confirmed Tsuga prefixes
- `aws_networkelb_*` - **CONFIRMED** (21 live metrics in the current Tsuga catalog; verified by exact-prefix search and 24-hour/30-day CLI enumeration)

## Discovery status
Discovery: completed in Stage 2 for the current Tsuga environment.
- Prefix preflight with exact matching confirmed 21 `aws_networkelb_*` metrics.
- Live catalog reconciliation result:
  - 21 metrics present in Tsuga
  - 5 Stage 1 candidate metrics missing in this environment: `aws_networkelb_active_flow_count_tls`, `aws_networkelb_active_flow_count_udp`, `aws_networkelb_client_tls_negotiation_error_count`, `aws_networkelb_security_group_blocked_flow_count_inbound_tls`, `aws_networkelb_security_group_blocked_flow_count_outbound_tls`
  - 6 live-only metrics added to the bundle: `aws_networkelb_consumed_lc_us_tcp`, `aws_networkelb_new_flow_count_tcp`, `aws_networkelb_processed_bytes_tcp`, `aws_networkelb_processed_packets`, `aws_networkelb_security_group_blocked_flow_count_inbound_tcp`, `aws_networkelb_unhealthy_routing_flow_count`
- Actual context fields confirmed broadly across the live catalog: `context.env`, `context.team`, `context.loadbalancer`, `context.availabilityzone`, `context.cloud.region`, and `context.cloud.account.id`
- `context.targetgroup` is present on host-health metrics, but not on reset/rejection/flow metrics, so target-group grouping is limited to the target-health section.
- Count-like NLB metrics are exposed in Tsuga as `summary` with `cumulative` temporality, and this bundle now uses `per-second` on count-like widgets by explicit user request.

## Top sources
1. https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-metrics.html
   Why: canonical metric list, dimensions, and "no traffic means no datapoints" behavior.
2. https://docs.aws.amazon.com/elasticloadbalancing/latest/network/introduction.html
   Why: NLB architecture, protocol support, target groups, and zonal node model.
3. https://docs.aws.amazon.com/elasticloadbalancing/latest/userguide/how-elastic-load-balancing-works.html
   Why: shared ELB routing, DNS, and zonal behavior context.
4. https://docs.aws.amazon.com/elasticloadbalancing/latest/network/target-group-health-checks.html
   Why: active/passive health checks, fail-open behavior, and zonal removal semantics.
5. https://docs.aws.amazon.com/elasticloadbalancing/latest/network/check-target-health.html
   Why: target states and reason codes for health-related triage.
6. https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-target-groups.html
   Why: target-group thresholds, DNS failover, and health-threshold behavior.
7. https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-access-logs.html
   Why: legacy TLS access-log format, path, and parser caveats.
8. https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-logs.html
   Why: enhanced log-delivery options and Stage 4 route implications.
9. https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-troubleshooting.html
   Why: operational failure modes including reset growth and port allocation errors.
10. https://aws.amazon.com/th/elasticloadbalancing/faqs/
   Why: LCU interpretation for NLB flow, active connection, and processed-byte dimensions.
11. https://docs.aws.amazon.com/en_us/elasticloadbalancing/latest/network/load-balancer-limits.html
   Why: quotas that affect capacity and saturation interpretation.
