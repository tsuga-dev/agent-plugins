# AWS NAT Gateway Integration Context Bundle

## Metadata
**Technology:** AWS NAT Gateway  
**Deployment:** managed  
**Environment:** prod  
**Persona:** SRE Dev and ops  
**Telemetry preference:** mixed  
**Integration scope:** core service only  
**Primary use-case:** reliability and performance

## How to use this bundle
- Use `01_aws-nat-gateway_metrics.csv` as the metric source of truth for NAT Gateway traffic, translation health, packet drops, and port pressure.
- Use `02_aws-nat-gateway_dashboard_plan.yaml` for section structure, widget definitions, derived signals, explanation notes, triage chains, and playbooks.
- Use `03_aws-nat-gateway_state.yaml` for machine-readable unknowns, assumptions, log-route handoff context, and Stage 2 verification targets.
- Use `04_aws-nat-gateway_memory.md` for the short narrative handoff into Stage 2.
- Stage 2 will create `05_aws-nat-gateway_metric_catalog.csv` as the discovered Tsuga metric inventory and description substrate.
- Stage 4 should read this file's `Log intelligence (Stage 4 handoff)` section and `03_aws-nat-gateway_state.yaml` `log_intel` block before proposing any route payload.

## What it is and what "good" looks like
### Confirmed by sources
AWS NAT Gateway is an AZ-scoped managed network address translation service that lets private subnets initiate outbound connections to the internet, other VPCs, or other networks through a translated source address. It exposes CloudWatch metrics for connection volume, translated byte and packet flow in each direction, active connections, failed port allocations, idle timeouts, dropped packets, and peak throughput. Good posture means outbound traffic is flowing in the expected direction, connection attempts are converting into established connections, `ErrorPortAllocation`, `IdleTimeoutCount`, and `PacketsDropCount` stay near zero, and peak throughput remains below the point where connection failures or drops start appearing.  
Sources: https://docs.aws.amazon.com/vpc/latest/userguide/metrics-dimensions-nat-gateway.html, https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-basics.html, https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-troubleshooting.html

### Best-practice inference
- Incident shape 1: outbound dependency traffic stalls while active connections remain high. Start in `translation-health` to check connection establishment success, then `drops-port-pressure`.
- Incident shape 2: burst traffic or fan-out change causes port exhaustion or packet drops. Start in `drops-port-pressure`.
- Incident shape 3: traffic volume looks healthy but response path collapses or return traffic skews. Start in `traffic-directionality`.

## Key concepts
### Glossary
| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| NAT Gateway | Managed AWS network address translator | Core egress path for private workloads | all sections |
| Private subnet | Subnet without direct internet ingress | Usually depends on NAT for outbound reachability | traffic-directionality |
| Public NAT gateway | NAT gateway backed by an Elastic IP | Common pattern for internet egress from private subnets | traffic-directionality |
| Private NAT gateway | NAT gateway without internet routing | Used for private network translation patterns | traffic-directionality |
| Source translation | Rewriting source IP/port on egress | Fundamental success path for outbound connections | translation-health |
| Connection attempt | A new outbound connection request seen by the gateway | Demand denominator for failure ratios | translation-health |
| Connection established | A connection successfully translated and opened | Health proxy for successful translation | translation-health |
| Active connection | Concurrent open translated connections | Saturation and concurrency pressure signal | connections-capacity |
| ErrorPortAllocation | CloudWatch metric for failed source-port allocation | Strong evidence of NAT capacity exhaustion per destination tuple | drops-port-pressure |
| Idle timeout | Connection closed after inactivity | Often signals long-lived idle flows or keepalive mismatch | translation-health |
| Packet drop | Packet not forwarded by the NAT gateway | Direct customer-impact symptom when sustained | drops-port-pressure |
| BytesInFromSource | Bytes entering NAT from private-side sources | Outbound request-side volume | traffic-directionality |
| BytesOutToDestination | Bytes exiting NAT toward destination | Forwarded outbound volume | traffic-directionality |
| BytesInFromDestination | Bytes returning from destination toward NAT | Response-side volume | traffic-directionality |
| BytesOutToSource | Bytes exiting NAT toward private-side source | Returned response volume | traffic-directionality |
| PacketsInFromSource | Packets entering NAT from private-side sources | Request packet-rate baseline | traffic-directionality |
| PacketsOutToDestination | Packets forwarded to destination | Outbound forwarding confirmation | traffic-directionality |
| PacketsInFromDestination | Packets returning from destination | Response path signal | traffic-directionality |
| PacketsOutToSource | Packets forwarded back to private source | End-to-end response delivery proxy | traffic-directionality |
| PeakBytesPerSecond | Highest byte throughput observed in the minute | Burstiness and headroom proxy | packet-shape-bursts |
| PeakPacketsPerSecond | Highest packet throughput observed in the minute | Packet-intensity burst proxy | packet-shape-bursts |
| Elastic IP | Public IP attached to a public NAT gateway | Important for internet egress identity and troubleshooting | traffic-directionality |
| Availability Zone | AZ containing the NAT gateway | Blast-radius boundary because NAT gateways are AZ-local | connections-capacity |
| VPC Flow Logs | VPC-level connection log records | Best Stage 4 fallback because NAT Gateway has no native service logs | translation-health |
| Traffic path | Flow Logs field indicating network path | Useful to distinguish internet/NAT path evidence when available | translation-health |

### Concept Map
```text
Private workload -> sends -> outbound packet to private subnet route table (why: NAT is reached only when routing sends egress to it)
Private subnet route table -> targets -> NAT gateway (why: routing decides whether egress uses NAT)
NAT gateway -> performs -> source IP and port translation (why: private sources need translated identity)
NAT gateway -> consumes -> source ports per destination tuple (why: port pool limits create exhaustion risk)
ConnectionAttemptCount -> represents -> new outbound connection demand (why: best denominator for establishment success)
ConnectionEstablishedCount -> represents -> successful translated sessions (why: confirms the gateway opened flows)
ActiveConnectionCount -> reflects -> concurrent live translated sessions (why: shows concurrency pressure)
ErrorPortAllocation -> indicates -> no source port available for a new flow (why: strong saturation symptom)
IdleTimeoutCount -> indicates -> connection expired after inactivity (why: long-lived idle protocols can fail without keepalives)
PacketsDropCount -> indicates -> packets were discarded (why: direct customer impact if sustained)
BytesInFromSource -> should lead to -> BytesOutToDestination (why: outbound requests should be forwarded)
BytesInFromDestination -> should lead to -> BytesOutToSource (why: return path should be delivered back to clients)
PacketsInFromSource -> should lead to -> PacketsOutToDestination (why: request packets traverse the translator)
PacketsInFromDestination -> should lead to -> PacketsOutToSource (why: response packets traverse back to workloads)
PeakBytesPerSecond -> bounds -> burst throughput intensity (why: average traffic can hide short spikes)
PeakPacketsPerSecond -> bounds -> burst packet intensity (why: packet-heavy workloads can fail before byte-heavy workloads)
One NAT gateway -> lives in -> one Availability Zone (why: outages and scaling are AZ-scoped)
One subnet -> should prefer -> same-AZ NAT gateway (why: reduces cross-AZ dependency and blast radius)
Destination service -> can stall -> response path bytes and packets (why: request traffic alone is not enough for success)
Keepalive mismatch -> increases -> IdleTimeoutCount (why: NAT expires idle state after 350 seconds)
Fan-out to same destination -> increases -> ErrorPortAllocation risk (why: per-destination connection scaling is bounded)
PacketsDropCount -> often follows -> burst or pressure events (why: sustained overload degrades forwarding)
Traffic skew by NAT gateway id -> reveals -> hot gateway or routing imbalance (why: one gateway can saturate before peers)
context.env -> scopes -> safe global dashboard filter (why: mixed environments distort burst and error baselines)
context.team -> scopes -> owner routing (why: NAT issues often map to platform or network owners)
context.cloud.region -> scopes -> regional blast radius (why: metrics aggregate differently across regions)
context.natgatewayid -> scopes -> resource-level triage (why: most NAT issues are per gateway, not per account)
Flow logs -> validate -> connection-level evidence when metrics are ambiguous (why: no native NAT access logs exist)
```

### Entities and dimensions
| Entity/Dimension | Why useful | Cardinality risk | Safe top-N | Do NOT group-by guidance |
|---|---|---|---|---|
| `context.natgatewayid` | Primary resource identity for troubleshooting | Low | 20 | Prefer as first-level grouping |
| `context.cloud.region` | Regional blast-radius split | Low | 10 | Usually a global filter in single-region deployments |
| `context.cloud.account.id` | Multi-account isolation | Low | 10 | Optional if single-account estate |
| `context.cloud.provider` | Confirms AWS-only scope and mixed-cloud hygiene | Low | 4 | Best used as a filter sanity check, not a chart split |
| `context.subnet.id` | Identifies private-side route source | Medium | 15 | Avoid top-level KPI groupings unless strongly bounded |
| `context.env` | Environment filter | Low | 5 | Use as a global filter, not a chart split |
| `context.team` | Ownership routing | Low | 10 | Use as a global filter, not a chart split |
| `context.route_table.id` | Helps debug wrong routing | Medium | 10 | Debug-only, not default widget split |
| `context.destination.address_family` | Distinguishes IPv4-only NAT path use | Low | 4 | Avoid unless dual-stack behavior matters |
| `context.destination.service` | Helps isolate fan-out hot spots | Medium | 10 | Only if a bounded service tag exists in Tsuga |
| `context.interface.id` | Useful for flow-log joins | Medium | 10 | Never use as a top-level dashboard grouping unless verified and bounded |
| `context.source.workload` | Maps egress to calling workload | Medium | 12 | Avoid if derived from pod/task identity without aggregation |
| `context.traffic_path` | Useful Flow Logs path evidence | Low | 6 | Log-only or debug-only unless verified in metrics |

### Tsuga field mapping
| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| NAT gateway ID | `context.natgatewayid` | Must-exist |
| Availability Zone | `Unknown` | Optional |
| AWS Region | `context.cloud.region` | Must-exist |
| AWS Account ID | `context.cloud.account.id` | Must-exist |
| VPC ID | `Unknown` | Optional |
| Subnet ID | `context.subnet.id` | Optional |
| Route table ID | `context.route_table.id` | Optional |
| Team tag | `context.team` | Must-exist |
| Environment tag | `context.env` | Must-exist |
| Cloud provider | `context.cloud.provider` | Must-exist |
| Exporter ARN | `context.aws.exporter.arn` | Optional |
| ENI / interface id for Flow Logs correlation | `context.interface.id` | Optional |

#### Confirmed by sources
AWS publishes NAT Gateway metrics per `NatGatewayId`, and NAT gateways themselves are AZ-scoped resources deployed in a VPC subnet.  
Sources: https://docs.aws.amazon.com/vpc/latest/userguide/metrics-dimensions-nat-gateway.html, https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-basics.html

#### Best-practice inference
Stage 2 confirmed the resource key is `context.natgatewayid`, but VPC-, subnet-, route-table-, and AZ-level dimensions are not present on the discovered NAT metrics and must not be assumed in dashboard queries.

## Golden signals
### Confirmed by sources
| Signal | NAT Gateway meaning | Typical degradations | Best telemetry sources | What people page on | Section questions |
|---|---|---|---|---|---|
| Traffic | Outbound and return byte/packet flow through translation | sudden traffic drop, directional skew, response path collapse | NAT Gateway CloudWatch bytes/packets metrics | "egress stopped", "return traffic vanished", "traffic burst exceeded normal" | Is traffic flowing both ways? Which gateway is hottest? |
| Errors | Failed translation or forwarding events | `ErrorPortAllocation`, `PacketsDropCount` spikes | NAT Gateway CloudWatch error metrics, VPC Flow Logs for evidence | "new connections fail", "packets dropped under load" | Are failures due to port exhaustion or packet drops? |
| Latency | No direct latency metric; use lifecycle proxies | `IdleTimeoutCount` growth, connection establishment gap, stalled return path | NAT Gateway metrics plus VPC Flow Logs for path evidence | "connections hang then fail", "idle sessions reset" | Are connections establishing and staying valid? |
| Saturation | Concurrency and burst pressure against a per-gateway translator | high `ActiveConnectionCount`, high peaks, rising port-allocation errors | Active connections, peak throughput, error metrics | "one gateway is hot", "burst traffic creates hard failures" | Are we approaching or exceeding safe NAT headroom? |

### Best-practice inference
For NAT Gateway, connection-establishment success and packet-drop rate are usually more actionable than a generic "availability" KPI because the service is binary only at the connection path. There is no first-class latency metric, so dashboard design should present lifecycle proxies and explicitly say they are proxies, not direct latency.

## Telemetry sources
### Confirmed by sources
| Source type | How collected | What it provides | Pros/cons | Common pitfalls |
|---|---|---|---|---|
| CloudWatch NAT Gateway metrics | AWS-native metrics | Canonical bytes, packets, connections, drops, port-allocation errors, idle timeouts, peaks | Best source for gateway health and load | No direct latency or per-destination breakdown |
| VPC Flow Logs | VPC/subnet/ENI flow logging | Connection-level records for src/dst/ports/action/log-status and optional path fields | Best evidence source when metrics show a gateway problem | Must be enabled; aggregation interval and field version affect usefulness |
| Route table / NAT configuration state | AWS control plane | Which private subnets use which NAT gateway and whether AZ-local routing is followed | Needed to understand blast radius and one-gateway hot spots | Not a metric source; configuration drift can explain metric skew |
| Exporter / collector normalization | Tsuga ingestion layer | Final `aws_natgateway_*` names and context field shapes | Determines dashboard query syntax | Naming/temporality may differ from CloudWatch expectations |

### Best-practice inference
- "No data" on CloudWatch NAT metrics can mean the gateway is idle, the gateway is absent from the selected account/region, or collector coverage is missing.
- "No data" on Flow Logs usually means Flow Logs were never enabled or the selected field version does not include the desired attributes.
- Optional features matter: private vs public NAT changes operational context, but the base metric family remains the same.

## Log intelligence (Stage 4 handoff)
### Confirmed by sources
1. **Log sources matrix**

| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|---|---|---|---|---|
| VPC Flow Logs to CloudWatch Logs or S3 | VPC / subnet / ENI flow log destination | Space-delimited record with versioned fields | Structured text | https://docs.aws.amazon.com/vpc/latest/userguide/flow-log-records.html |
| NAT Gateway metrics + troubleshooting context | CloudWatch metrics and AWS console | Metrics only, not raw logs | Structured metrics only | https://docs.aws.amazon.com/vpc/latest/userguide/metrics-dimensions-nat-gateway.html |
| NAT Gateway troubleshooting docs | AWS docs | Narrative examples and failure explanations | Unstructured documentation | https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-troubleshooting.html |

2. **Known log formats**
- **VPC Flow Logs default format**
  - Sample line: `2 123456789012 eni-abc123 10.0.1.10 52.95.110.1 49152 443 6 10 840 1709980000 1709980060 ACCEPT OK`
  - Delimiter/shape notes: space-delimited positional fields.
  - Timestamp pattern: Unix epoch seconds for `start` and `end`.
  - Quoting behavior: none in default format.
  - Optional fields: custom formats can add fields such as `pkt-srcaddr`, `pkt-dstaddr`, `traffic-path`, `az-id`, or subnet metadata when supported.

3. **Candidate query filters for Stage 4**
- Precise: `context.service.name:vpc-flow-logs AND (context.natgatewayid:* OR message:*nat-*gateway*)`
  - Rationale: best if the ingestion pipeline already maps NAT gateway identity or source ENI metadata.
  - Risk: likely misses data if NAT gateway identity is not normalized into Tsuga log attributes.
- Fallback: `context.service.name:vpc-flow-logs AND (dstport:443 OR dstport:80 OR action:REJECT OR log-status:SKIPDATA)`
  - Rationale: broad enough to capture common egress flows and failure evidence for NAT-heavy paths.
  - Risk: captures more non-NAT traffic and needs refinement by VPC/subnet/interface context.

4. **Attribute mapping hints**

| Raw field | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| `interface-id` | `context.interface.id` | medium | Useful join field if NAT ENI mapping is known |
| `srcaddr` | `network.client.ip` | medium | Private source workload IP for request-side flow |
| `dstaddr` | `network.destination.ip` | medium | Destination service IP |
| `srcport` | `network.client.port` | medium | Useful when debugging ephemeral-port churn |
| `dstport` | `network.destination.port` | high | Critical for egress protocol/service breakdown |
| `protocol` | `network.transport` | medium | Numeric in raw logs; requires mapping |
| `packets` | `network.packets` | high | Good for failure-volume evidence |
| `bytes` | `network.bytes` | high | Good for traffic evidence |
| `action` | `event.outcome` | high | Map ACCEPT/REJECT carefully |
| `log-status` | `aws.vpc.flow_log.status` | high | Important for missing-data interpretation |
| `traffic-path` | `context.traffic_path` | medium | Valuable when enabled; not guaranteed in every format |

5. **Parsing risks**
- Flow Log field set is version-dependent; do not assume `traffic-path` or packet-level address fields exist.
- Records are positional, so the parser must match the exact configured format.
- NAT Gateway itself has no native access log, so route logic must not pretend there is a NAT-specific raw log stream.
- Interface-to-NAT-gateway resolution may need AWS inventory enrichment outside the log line itself.

### Best-practice inference
Stage 4 should treat VPC Flow Logs as the primary evidence stream and keep NAT-specific parsing conservative. If NAT gateway id is not directly present in the logs, the first viable route may need to key off VPC, subnet, or ENI metadata rather than a clean NAT gateway attribute.

## Caveats and footguns
- **[traffic-directionality]** `BytesInFromSource` and `BytesOutToDestination` are request-side path metrics; they do not prove the response path is healthy. (https://docs.aws.amazon.com/vpc/latest/userguide/metrics-dimensions-nat-gateway.html)
- **[traffic-directionality]** `BytesInFromDestination` and `BytesOutToSource` can fall even when outbound traffic is healthy if the upstream dependency is stalling or rejecting. (Inference)
- **[traffic-directionality]** Packet and byte asymmetry is normal for request/response protocols; alert only on material baseline shift, not perfect symmetry. (Inference)
- **[translation-health]** NAT Gateway exposes no direct latency metric; any "latency" widget is a proxy and must be labeled as such. (https://docs.aws.amazon.com/vpc/latest/userguide/metrics-dimensions-nat-gateway.html)
- **[translation-health]** `IdleTimeoutCount` reflects idle-flow expiry after 350 seconds and is often application keepalive mismatch, not gateway unavailability. (https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-troubleshooting.html)
- **[translation-health]** `ConnectionAttemptCount` without `ConnectionEstablishedCount` gap growth can still hide app-level failure beyond the gateway. (Inference)
- **[translation-health]** A low establishment-success ratio can be caused by destination refusal or routing drift, not only NAT pressure. (Inference)
- **[translation-health]** Flow Logs `ACCEPT` does not prove the full application request succeeded; it only proves the network flow record outcome. (https://docs.aws.amazon.com/vpc/latest/userguide/flow-log-records.html)
- **[connections-capacity]** NAT gateways are AZ-scoped, so summing active connections across AZs can hide a single hot gateway. (https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-basics.html)
- **[connections-capacity]** Cross-AZ private-subnet routing to a different AZ's NAT gateway increases blast radius and can distort one-gateway saturation. (https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-basics.html)
- **[connections-capacity]** `ActiveConnectionCount` is a gauge; do not rate-normalize it. (Inference)
- **[connections-capacity]** Peak metrics are maxima over a minute and can look scary next to average throughput even when sustained load is moderate. (Inference)
- **[drops-port-pressure]** `ErrorPortAllocation` is the most direct hard-failure signal for port exhaustion and should not be averaged away into long windows. (https://docs.aws.amazon.com/vpc/latest/userguide/metrics-dimensions-nat-gateway.html)
- **[drops-port-pressure]** Port-allocation failures are destination-sensitive; a single hot destination can fail while total traffic still looks normal. (https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-troubleshooting.html)
- **[drops-port-pressure]** `PacketsDropCount` proves forwarding loss but not root cause by itself; correlate with peaks and port-allocation errors. (https://docs.aws.amazon.com/vpc/latest/userguide/metrics-dimensions-nat-gateway.html)
- **[drops-port-pressure]** Low absolute error counts can still matter if the environment has few connection attempts; ratios need denominator context. (Inference)
- **[packet-shape-bursts]** `PeakBytesPerSecond` and `PeakPacketsPerSecond` can spike without any customer issue if the system is bursty but below failure thresholds. (Inference)
- **[packet-shape-bursts]** Byte-heavy and packet-heavy workloads stress different limits; do not assume one peak metric is sufficient. (Inference)
- **[packet-shape-bursts]** Average throughput alone hides burst headroom problems; always pair it with peak metrics. (https://docs.aws.amazon.com/vpc/latest/userguide/metrics-dimensions-nat-gateway.html)
- **[traffic-directionality, translation-health]** Resource-level triage depends on `context.natgatewayid`; if that key disappears from ingestion, the dashboard must fall back to region-only grouping. (Stage 2 discovery)
- **[translation-health, drops-port-pressure]** The discovered NAT counters are all `summary/cumulative` in Tsuga, so counter widgets must use `rate` instead of `per-second`. (Stage 2 discovery)
- **[packet-shape-bursts]** Peak-to-average ratios are diagnostic heuristics, not official AWS health indicators. (Inference)
- **[connections-capacity, drops-port-pressure]** No cost metric exists in the base NAT Gateway metric family; do not invent a cost dashboard section from throughput alone. (Inference)

## Confirmed Tsuga prefixes
- `aws_natgateway_*` — **CONFIRMED** (16/16 operational NAT metrics present in Tsuga discovery; matched by `tools/tsuga_search_metrics.py '^aws_natgateway_.*'`)

## Discovery status
Discovery: completed in Stage 2.
- Metrics found: 16 total
- Metrics confirmed from `01`: 16
- Missing from `01`: 0
- Unexpected additional metrics: 0
- Confirmed reusable context keys: `context.natgatewayid`, `context.cloud.region`, `context.cloud.account.id`, `context.cloud.provider`, `context.env`, `context.team`
- All discovered NAT metrics report `type=summary` and `temporality=cumulative`; counters were reconciled to use `rate`

## Top sources
1. https://docs.aws.amazon.com/vpc/latest/userguide/metrics-dimensions-nat-gateway.html  
   Why: canonical NAT Gateway metric names, meanings, and dimensions.
2. https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-basics.html  
   Why: architecture, AZ scope, and operational behavior.
3. https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-troubleshooting.html  
   Why: key failure modes such as idle timeout and port-allocation exhaustion.
4. https://docs.aws.amazon.com/vpc/latest/userguide/flow-log-records.html  
   Why: VPC Flow Logs schema and field options for Stage 4.
5. https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-working-with.html  
   Why: lifecycle and operational management context for gateways.
6. https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html  
   Why: service overview and public/private NAT positioning.
7. https://docs.aws.amazon.com/vpc/latest/userguide/route-table-options.html#route-tables-nat-device  
   Why: route-table behavior that explains blast radius and skew.
8. https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs-records-examples.html  
   Why: concrete Flow Logs examples to guide Stage 4 parsing.
9. https://docs.aws.amazon.com/vpc/latest/userguide/amazon-vpc-limits.html  
   Why: quota context for related VPC constructs and NAT planning.
10. https://docs.aws.amazon.com/whitepapers/latest/building-scalable-secure-multi-vpc-network-infrastructure/using-nat-gateway-for-centralized-egress.html  
    Why: architecture pattern context for hot-gateway and shared-egress scenarios.
