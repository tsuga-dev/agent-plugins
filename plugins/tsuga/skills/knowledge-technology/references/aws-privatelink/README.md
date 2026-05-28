# AWS PrivateLink Integration Context Bundle

**Technology**: AWS PrivateLink
**Deployment**: Managed cloud service
**Environment**: Production
**Persona Focus**: SRE, Dev, and Ops
**Telemetry Preference**: Mixed (AWS CloudWatch native + VPC Flow Logs + Route 53 query logs)
**Integration Scope**: Core service only (VPC endpoints and endpoint services; excludes gateway endpoints, VPC peering, Transit Gateway)
**Primary Use-Case**: Reliability and performance monitoring
**Bundle Created**: 2026-02-10
**Bundle Version**: 1.0

---

## How to use this bundle

This bundle provides everything needed to build production-ready Tsuga dashboards for AWS PrivateLink. **Start with 07** (`07_aws-privatelink_dashboard_plan.yaml`) for the complete dashboard structure and widget specifications. **Refer to 05** (`05_aws-privatelink_metric_inventory.csv`) for the source-of-truth metric definitions, including units, aggregations, and temporality. **Use 09** (`09_aws-privatelink_section_notes_and_playbooks.md`) for all dashboard note content (mission note, section notes, triage chains, playbooks).

**For Stage 2 (metric discovery)**: The "Confirmed Tsuga prefixes" section below provides the starting point for API discovery. All counter metrics have temporality marked as **VERIFY** in files 05 and 07; Stage 2 will resolve delta vs cumulative via `/v1/metrics/metadata` endpoint.

**For Stage 3 (dashboard creation)**: Use the dashboard plan (07), metric inventory (05), derived signals (06), and section notes (09) as implementation blueprints. All widgets reference exact metric names, aggregations, post-functions, and normalizers. Quality gates script (`tools/tsuga_quality_gates.py`) will validate payloads before submission.

---

## Confirmed Tsuga prefixes

- **`aws_privatelinkendpoints_*`** — **CONFIRMED** (PrivateLink consumer/provider CloudWatch metrics)
  **Evidence**: 6 metrics found in Tsuga (5 expected + 1 unexpected). Naming is `aws_privatelinkendpoints_*` (NOT `aws_privatelink_*` as initially assumed). Metrics: `aws_privatelinkendpoints_active_connections`, `aws_privatelinkendpoints_new_connections`, `aws_privatelinkendpoints_bytes_processed`, `aws_privatelinkendpoints_packets_dropped`, `aws_privatelinkendpoints_rst_packets_received`, `aws_privatelinkservices_endpoints_count` (unexpected). All are type `summary` with `cumulative` temporality.
  **Source**: [AWS PrivateLink CloudWatch metrics documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/privatelink-cloudwatch-metrics.html) + Tsuga API discovery

- **`aws_networkelb_*`** — **CONFIRMED** (NLB backend target health metrics for provider-side monitoring)
  **Evidence**: 3/4 expected NLB metrics found in Tsuga. Naming is `aws_networkelb_*` (NOT `aws_nlb_*`). Metrics: `aws_networkelb_healthy_host_count`, `aws_networkelb_un_healthy_host_count` (note underscore in "un_healthy"), `aws_networkelb_processed_bytes`. MISSING: `target_connection_error_count` (not ingested). Alternative proxy metric available: `aws_networkelb_tcp_target_reset_count`. All are type `summary` with `cumulative` temporality.
  **Source**: [AWS NLB CloudWatch metrics documentation](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-metrics.html) + Tsuga API discovery

**Discovery strategy for Stage 2**:
1. Query Tsuga API `/v1/metrics/names-and-types?namespace=aws_privatelink*&from=<timestamp>&to=<timestamp>` to list all PrivateLink metrics with dimensions
2. Query `/v1/metrics/metadata` for each metric to confirm `type` (gauge vs summary) and `temporality` (delta vs cumulative) for counters
3. Query `/v1/metrics/names-and-types?namespace=aws_nlb*` OR `namespace=aws_networkloadbalancer*` to locate NLB metrics
4. Validate context field names (context.endpointid vs context.endpoint_id; context.availabilityzone vs context.az)
5. Check for optional dimensions (context.region for cross-region deployments; context.connectionstate if state metrics exist)

---

## Discovery status

**Discovery**: ✅ COMPLETED (Stage 2 finished 2026-02-10)
**Metrics found**: 10 total (6 PrivateLink + 4 NLB) = **90% coverage**
- PrivateLink: 5/5 expected + 1 unexpected (`endpoints_count`) = 6 metrics
- NLB: 3/4 expected (missing `target_connection_error_count`) = 4 metrics (including `processed_bytes` excluded from dashboards)
**High-impact unknowns**: 0 (all resolved during Stage 2)
**Coverage**: Consumer-side 100% (all 5 PrivateLink metrics confirmed); provider-side 75% (3/4 NLB metrics, 1 missing)

**CRITICAL DISCOVERY FINDINGS:**
1. **Metric naming**: `aws_privatelinkendpoints_*` and `aws_networkelb_*` (NOT `aws_privatelink_*` or `aws_nlb_*`)
2. **Temporality**: ALL counters are cumulative → use `rate` post-function (NOT `per-second`)
3. **Context fields**: Use SPACE-SEPARATED names: `context.vpc endpoint id` (NOT `context.endpointid`)
4. **NO Availability Zone dimension**: Per-AZ bandwidth analysis IMPOSSIBLE; major dashboard limitation
5. **Missing metric**: NLB `target_connection_error_count` not found; use `tcp_target_reset_count` as proxy

**Files updated**: 05 (metric inventory corrected), 00 (this file - prefix status updated), 12 (reconciliation report created)

---

## Bundle files

| # | Filename | Purpose |
|---|---|---|
| 00 | `00_aws-privatelink_cover.md` | Bundle overview, metadata, Tsuga prefix handoff, top sources |
| 01 | `01_aws-privatelink_executive_overview.md` | What it is, where it runs, what "good" looks like, top 3 incident shapes, paging intent |
| 02 | `02_aws-privatelink_key_concepts.md` | Glossary (24 terms), concept map (28 relationships), entities/dimensions (12), Tsuga field mapping |
| 03 | `03_aws-privatelink_golden_signals.md` | Traffic/Errors/Latency/Saturation definitions, causes, telemetry sources, paging symptoms, section questions |
| 04 | `04_aws-privatelink_telemetry_sources.md` | Source matrix (8 sources), optional features, "no data" meanings, source coverage map |
| 05 | `05_aws-privatelink_metric_inventory.csv` | Source-of-truth metric definitions (17 metrics: 5 PrivateLink + 4 NLB + 8 derived/proxy), units, temporality, aggregations, group-by |
| 06 | `06_aws-privatelink_derived_signals.csv` | Formula widgets (12 derived signals: bandwidth utilization, reset rate, cost calculations, backend health ratio) |
| 07 | `07_aws-privatelink_dashboard_plan.yaml` | Dashboard structure (2 dashboards: overview + deep dive), 4 sections, 40+ widgets, coverage map |
| 09 | `09_aws-privatelink_section_notes_and_playbooks.md` | Mission note, 4 section explanation notes, 20 triage chains, 7 operational playbooks |
| 10 | `10_aws-privatelink_caveats_footguns.md` | 33 caveats across 6 categories (cardinality, misleading metrics, units, temporality, false alarms, optional features) |
| 11 | `11_aws-privatelink_unknowns_verify_next.yaml` | 10 unknowns (3 high-impact, 3 medium-impact, 4 low-impact) with verification steps and UI reflection strategies |

---

## Top sources (Stage 3 "Learn more" links)

1. **[CloudWatch metrics for AWS PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/privatelink-cloudwatch-metrics.html)** — Official AWS documentation defining all 5 PrivateLink CloudWatch metrics (ActiveConnections, NewConnections, BytesProcessed, PacketDropCount, ResetPacketsReceived), namespaces (AWS/PrivateLinkEndpoints, AWS/PrivateLinkServices), and 1-minute granularity. Primary source for metric definitions in 05.

2. **[AWS PrivateLink concepts](https://docs.aws.amazon.com/vpc/latest/privatelink/concepts.html)** — Core architecture documentation explaining interface VPC endpoints, VPC endpoint services, service consumers, service providers, Network Load Balancer requirements, and connection lifecycle. Foundation for 01 (executive overview) and 02 (key concepts).

3. **[Configure an endpoint service](https://docs.aws.amazon.com/vpc/latest/privatelink/configure-endpoint-service.html)** — Service provider configuration guide covering connection acceptance (manual vs automatic), allowed principals, endpoint service states, and NLB integration. Source for connection state definitions (Pending, Available, Rejected, Failed, Expired) used in 01 and 02.

4. **[Fix network performance issues with AWS PrivateLink endpoints](https://repost.aws/knowledge-center/vpc-troubleshoot-network-performance-privatelink)** — AWS re:Post knowledge article documenting 10 Gbps baseline, 100 Gbps auto-scaling, 350-second idle timeout, PacketDropCount troubleshooting, and MTU mismatch issues. Critical source for 03 (golden signals) and 10 (caveats).

5. **[Gain usage insights with Amazon CloudWatch metrics for AWS PrivateLink](https://aws.amazon.com/blogs/networking-and-content-delivery/gain-usage-insights-with-amazon-cloudwatch-metrics-for-aws-privatelink/)** — AWS blog announcing Contributor Insights integration for PrivateLink, including top-N consumer endpoint ranking by BytesProcessed, ActiveConnections, NewConnections, ResetPacketsReceived. Source for 04 (telemetry sources) Contributor Insights section.

6. **[AWS PrivateLink pricing](https://aws.amazon.com/privatelink/pricing/)** — Official pricing page documenting hourly endpoint charges ($0.01/hour interface, $0.02/hour resource), data processing charges (tiered: $0.01/GB, $0.006/GB, $0.004/GB), and cross-region data transfer charges ($0.02/GB surcharge). Primary source for cost metrics in 05 and 06.

7. **[Introducing cross-region connectivity for AWS PrivateLink](https://aws.amazon.com/blogs/networking-and-content-delivery/introducing-cross-region-connectivity-for-aws-privatelink/)** — AWS blog announcing November 2025 launch of cross-region PrivateLink, explaining consumer-provider region mismatch support, IAM permissions (vpce:AllowMultiRegion), and multi-region architecture patterns. Source for cross-region cost analysis in 05, 06, 07.

8. **[CloudWatch metrics for Network Load Balancers](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-metrics.html)** — Official AWS documentation for NLB metrics including HealthyHostCount, UnHealthyHostCount, TargetConnectionErrorCount, ProcessedBytes, health check semantics. Primary source for backend target health metrics in 05 (provider-side monitoring).

9. **[Health checks for Network Load Balancer target groups](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/target-group-health-checks.html)** — NLB health check configuration guide covering health check intervals, thresholds, active vs passive health checks, and target state transitions. Source for backend health troubleshooting in 09 (playbook 4).

10. **[Troubleshoot connectivity between VPC endpoint and endpoint service](https://repost.aws/knowledge-center/connect-endpoint-service-vpc)** — AWS re:Post troubleshooting guide for connection failures, security group misconfigurations, DNS resolution issues, and endpoint state diagnostics. Source for 09 (playbook 1: connection establishment failure) and 10 (connectivity footguns).

11. **[Working with private hosted zones — Route 53](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-private.html)** — Route 53 documentation on private hosted zones for PrivateLink private DNS, VPC associations, split-horizon DNS, and query logging. Source for 02 (key concepts) DNS sections and 09 (playbook 7: DNS resolution failure).

12. **[VPC Flow Logs documentation](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html)** — Official AWS guide to VPC Flow Logs for ENI-level traffic visibility, REJECT action analysis (security group denials), and flow log aggregation windows (1-10 minutes). Source for 04 (telemetry sources) VPC Flow Logs section and 09 (triage chains using Flow Logs).

---

## Stage 2 handoff checklist

- [x] Tsuga metric namespace prefixes documented with status labels (INFERRED)
- [x] Discovery strategy documented (which API endpoints to query, what to validate)
- [x] All counter metrics marked with temporality VERIFY in 05 and 07
- [x] Context field names include fallback options in 05 group_by column
- [x] Unknowns file (11) documents all high and medium impact verification needs
- [x] Top sources list includes >= 10 URLs with justifications
- [x] Bundle files table complete with all 11 files
- [x] Discovery status section explains what Stage 2 will resolve

---

## Validation results (self-check before Stage 2)

- ✅ Metric name claims cited or marked inferred (05: all metrics have citations or "Inference" notes)
- ✅ 07 coverage: all tsuga-mapped metrics from 05 included or excluded with reason (coverage_map complete)
- ✅ 07 → 09 consistency: all sections in 07 have matching note blocks in 09, all widget titles referenced in 09 exist in 07
- ✅ 06 → 05 consistency: all `input_metrics` in 06 exist in 05 (verified: all derived signals reference valid base metrics)
- ✅ 06 → 07 consistency: all `section_id` in 06 exist in 07, all formula widgets in 07 have matching rows in 06
- ✅ 10 → 07 consistency: all section tags in 10 match section ids in 07 (verified: all caveats tagged correctly)
- ✅ No jammed multi-metric widgets without single derived-signal purpose (all multi-query widgets in 07 have clear purpose)
- ✅ Counter temporality guidance exists (05: post_function column has per-second|rate; 07: widgets have # VERIFY comments)
- ✅ Optional features gated (cross-region, NLB provider-side, Contributor Insights sections include gating language)
- ✅ Stage 2 handoff ready: "Confirmed Tsuga prefixes" section complete with evidence and status labels
- ✅ Temporality markers: Counter metrics in 05 have `post_function` guidance; widget specs in 07 include `# VERIFY` comments

---

## Summary

This bundle provides **comprehensive monitoring coverage** for AWS PrivateLink across **consumer-side** (VPC endpoints) and **provider-side** (VPC endpoint services) perspectives. Two dashboards (overview KPI wall + deep dive operational investigation) cover **4 major sections**: Endpoint Connection Health, Data Transfer & Network Performance, Backend Target Health (provider-side), and Cost & Usage.

**Strengths**: Grounded in official AWS documentation (12 primary sources), includes operational playbooks and triage chains (20 chains, 7 playbooks), comprehensive caveats (33 footguns documented), and clear unknowns tracking (10 items with verification strategies).

**Limitations**: Counter temporality unconfirmed (affects all rate calculations; marked for Stage 2 verification), NLB metric namespace unknown (backend health section may be partial coverage), connection state metrics may not exist as CloudWatch metrics (endpoint state distribution may require API calls vs dashboard widgets).

**Next step**: Proceed to Stage 2 (metric discovery & reconciliation) using Tsuga API to resolve all high and medium impact unknowns.


---

# AWS PrivateLink — Executive Overview

## What it is
AWS PrivateLink is a managed networking service that enables private connectivity between VPCs, AWS services, and on-premises networks without exposing traffic to the public internet. Service providers host services behind Network Load Balancers in their VPCs and expose them as VPC endpoint services. Consumers create interface VPC endpoints in their VPCs that connect privately to these services using AWS's internal network backbone.

## Where it runs
PrivateLink operates within AWS VPCs across single or multiple accounts and regions. Interface VPC endpoints are deployed as elastic network interfaces (ENIs) within consumer VPC subnets across one or more Availability Zones. The service provider side anchors a Network Load Balancer (NLB) in their VPC, with target health checks ensuring backend availability.

## What "good" looks like
Healthy PrivateLink deployments maintain stable active connections with minimal new connection churn, process data within bandwidth limits (10-100 Gbps per AZ), and report zero or near-zero packet drops and RST resets. Endpoint connection states remain "Available" (not "Pending" or "Rejected"), and backing NLB targets stay "InService" with passing health checks. DNS resolution succeeds instantly for private DNS-enabled endpoints.

## Paging intent
**Primary symptom**: Connection failures or timeouts when consumers attempt to reach endpoint services → indicates endpoint misconfiguration, security group blocks, or endpoint service unavailability.
**Secondary symptom**: Elevated packet drops (PacketDropCount) or RST resets (ResetPacketsReceived) → signals network congestion, bandwidth saturation, idle timeout issues, or application-layer problems.
**Tertiary symptom**: NLB target health failures → backend service degradation or misconfigured health checks impacting service availability.

## Top 3 incident shapes and triage starting points

**1. Connection establishment failures** (timeouts, rejections, "connection refused")
- **Symptoms**: NewConnections dropping to zero, consumers timing out, endpoint state "Rejected" or "Failed"
- **First dashboard section**: **Endpoint Connection Health** — check connection states, acceptance/rejection counts, security group denials
- **Common causes**: Endpoint connection request not accepted by provider, security group rules blocking traffic, DNS resolution failures, cross-AZ or cross-region connectivity misconfiguration

**2. Active connection disruptions** (RST packets, packet drops, throughput degradation)
- **Symptoms**: ActiveConnections dropping unexpectedly, ResetPacketsReceived spiking, PacketDropCount elevated, BytesProcessed fluctuating
- **First dashboard section**: **Data Transfer & Network Performance** — examine packet drops, RST counts, bytes processed, bandwidth saturation
- **Common causes**: Idle timeout exceeded (350s default), MTU mismatches, bandwidth quota exceeded (10 Gbps baseline), NLB unhealthy targets, application-layer connection closures

**3. Backend service unavailability** (target health failures, service provider issues)
- **Symptoms**: Connections established but requests failing, increased latency, intermittent errors
- **First dashboard section**: **Backend Target Health** (provider-side) — monitor NLB target health status, health check failures, target group metrics
- **Common causes**: NLB targets failing health checks, target auto-scaling lag, provider endpoint service disabled or deleted, listener port mismatches

---

## Confirmed by sources
- PrivateLink metrics (ActiveConnections, NewConnections, BytesProcessed, PacketDropCount, ResetPacketsReceived) are published to CloudWatch in 1-minute intervals ([AWS docs](https://docs.aws.amazon.com/vpc/latest/privatelink/privatelink-cloudwatch-metrics.html))
- Endpoint connection states: Available, Pending, Rejected, Expired, Failed ([AWS docs](https://docs.aws.amazon.com/vpc/latest/privatelink/configure-endpoint-service.html))
- 350-second idle timeout for PrivateLink endpoints ([AWS re:Post](https://repost.aws/knowledge-center/vpc-troubleshoot-network-performance-privatelink))
- 10 Gbps baseline with auto-scaling to 100 Gbps per AZ ([AWS re:Post](https://repost.aws/knowledge-center/vpc-troubleshoot-network-performance-privatelink))

## Best-practice inference
- Paging priority ordering (connection failures > network disruptions > backend health) follows standard incident triage patterns (user-facing impact first)
- Multi-AZ endpoint deployment for high availability aligns with AWS Well-Architected reliability pillar
- DNS resolution as a critical failure mode inferred from split-horizon DNS patterns and Route 53 integration complexity


---

# AWS PrivateLink — Key Concepts

## Glossary (dashboard-relevant definitions)

**Interface VPC Endpoint**: An elastic network interface (ENI) deployed in a consumer VPC subnet that serves as the entry point for private traffic to an endpoint service. Appears in all dashboard sections as the primary monitored entity.

**VPC Endpoint Service**: A service hosted by a provider behind a Network Load Balancer, exposed for private consumption via PrivateLink. Service-side metrics (AWS/PrivateLinkServices namespace) are monitored in provider dashboards.

**Endpoint Network Interface (ENI)**: The actual ENI resource backing an interface VPC endpoint, assigned a private IP from the consumer's subnet. ENI per-AZ determines bandwidth scaling and fault isolation boundaries.

**Service Consumer**: The AWS account that creates interface VPC endpoints to access a PrivateLink-enabled service. Consumes endpoint metrics (AWS/PrivateLinkEndpoints namespace).

**Service Provider**: The AWS account that hosts a VPC endpoint service and exposes it for consumption. Monitors service metrics (AWS/PrivateLinkServices namespace) and endpoint-specific contributor insights.

**Network Load Balancer (NLB)**: The AWS load balancer type required for PrivateLink endpoint services. NLB health checks and target states directly impact endpoint service availability.

**Connection Request**: A consumer-initiated request to connect their interface endpoint to a provider's endpoint service. Requires acceptance if the service is configured with manual approval. Tracked via connection state transitions.

**Connection State**: The lifecycle state of an endpoint connection: Pending (awaiting acceptance), Available (active), Rejected (denied by provider), Expired (timed out), Failed (error). Drives the "Endpoint Connection Health" dashboard section.

**Allowed Principal**: An IAM principal (user, role, account) granted permission by the service provider to create endpoint connections. Principal management affects connection acceptance rates.

**Acceptance Required**: A service-side configuration that mandates manual approval of connection requests. When enabled, new connections remain in "Pending" state until accepted, affecting NewConnections and connection latency.

**Cross-Region Connectivity**: PrivateLink feature allowing consumers in one AWS region to connect to endpoint services in another region. Introduced in 2025; adds inter-region data transfer costs and latency.

**Private DNS**: A feature that associates a custom DNS name with an interface endpoint, enabling transparent service access using familiar DNS names instead of endpoint-specific DNS entries. Requires Route 53 private hosted zone management.

**Split-Horizon DNS**: A DNS configuration pattern where the same domain name resolves to public IPs externally and private endpoint IPs internally. Commonly used with PrivateLink to maintain consistent service addressing.

**Idle Timeout**: A 350-second inactivity window after which AWS terminates a TCP connection through a PrivateLink endpoint. Clients/targets must send TCP keepalive packets to prevent resets. Drives RST packet metrics.

**Packet Drop**: Network packets discarded by the PrivateLink endpoint, typically due to bandwidth saturation (exceeding 10 Gbps baseline) or MTU mismatches. Tracked via PacketDropCount metric in "Data Transfer & Network Performance" section.

**RST Reset (TCP RST)**: A TCP reset packet sent to terminate a connection, often triggered by idle timeout expiration, application errors, or misconfigurations. Tracked via ResetPacketsReceived metric.

**Target Health**: The NLB health check status for backend instances behind a PrivateLink endpoint service. Unhealthy targets cause service degradation visible in consumer-side metrics (packet drops, connection failures).

**Contributor Insights Rule**: A pre-built CloudWatch rule for endpoint services that identifies which consumer endpoints are the top contributors to traffic (BytesProcessed), connections (ActiveConnections, NewConnections), or resets (ResetPacketsReceived). Used for capacity planning and abuse detection.

**Data Processing Charge**: A PrivateLink cost component charged per GB of data transferred through an interface endpoint. Tiered pricing: $0.01/GB (first PB), $0.006/GB (next 4 PB), $0.004/GB (5+ PB). Tracked via BytesProcessed metric in the "Cost & Usage" section.

**Hourly Endpoint Charge**: A fixed $0.01/hour cost per interface endpoint or $0.02/hour per resource endpoint. Drives the "Endpoint Count & Cost" section.

**Availability Zone (AZ) Mapping**: The alignment of consumer endpoint ENIs and provider NLB nodes across AZs. Multi-AZ deployment required for high availability; affects fault isolation and bandwidth scaling.

**Gateway Load Balancer (GWLB) Endpoint**: A specialized PrivateLink endpoint type for traffic inspection services (firewalls, IDS/IPS). Uses the same metrics as interface endpoints but serves a different architectural role.

**Endpoint Policy**: An IAM policy attached to an interface endpoint that restricts which IAM principals can use the endpoint and which actions they can perform. Misconfigured policies cause connection denials.

**Route 53 Profile**: A shareable DNS configuration for PrivateLink endpoints, enabling centralized private hosted zone management across multiple VPCs and accounts via AWS RAM. Simplifies split-horizon DNS at scale.

---

## Concept map (operational relationships)

**Service Consumer** -> creates -> **Interface VPC Endpoint** (establishes private connectivity without internet gateway/NAT)

**Interface VPC Endpoint** -> deploys -> **Endpoint Network Interface (ENI)** per AZ (determines bandwidth, fault isolation, and HA)

**Interface VPC Endpoint** -> sends -> **Connection Request** to **VPC Endpoint Service** (initiates consumer-provider relationship)

**Connection Request** -> transitions through -> **Connection State** (Pending -> Available/Rejected/Expired/Failed) (affects service reachability and troubleshooting)

**VPC Endpoint Service** -> checks -> **Allowed Principal** list (controls who can connect; missing principal causes rejections)

**VPC Endpoint Service** -> requires -> **Acceptance Required** flag (manual vs auto approval; impacts NewConnections latency)

**VPC Endpoint Service** -> backed by -> **Network Load Balancer (NLB)** (all PrivateLink services require NLB; no ALB/CLB support)

**Network Load Balancer** -> performs -> **Target Health** checks (backend availability; failures cascade to endpoint-side metrics)

**NLB Target Health** -> failing -> causes -> **Packet Drop** and **RST Reset** at endpoint (backend issues visible in consumer CloudWatch)

**Interface VPC Endpoint** -> enforces -> **Idle Timeout** (350s default; no traffic = TCP RST sent)

**Idle Timeout** -> exceeded -> triggers -> **RST Reset** (ResetPacketsReceived spikes; long-lived connections need keepalive)

**Interface VPC Endpoint** -> has -> **Bandwidth Quota** (10 Gbps baseline, auto-scales to 100 Gbps per AZ) (quota exceeded = PacketDropCount rises)

**BytesProcessed** -> exceeds -> **Bandwidth Quota** per AZ -> triggers -> **Packet Drop** (visible in Data Transfer & Network Performance section)

**Interface VPC Endpoint** -> optionally enables -> **Private DNS** (resolves service DNS to private IPs; simplifies client configuration)

**Private DNS** -> requires -> **Route 53 Private Hosted Zone** (DNS resolution within VPC; misconfiguration = connection failures)

**Route 53 Private Hosted Zone** -> supports -> **Split-Horizon DNS** (same domain, public vs private resolution; used for seamless migration)

**Interface VPC Endpoint** -> can enable -> **Cross-Region Connectivity** (consumer in us-east-1, service in eu-west-1; adds inter-region data transfer costs)

**Cross-Region Connectivity** -> incurs -> **$0.02/GB inter-region charge** on top of **Data Processing Charge** (cost visibility critical in Cost & Usage section)

**VPC Endpoint Service** -> publishes -> **Contributor Insights Rule** (identifies top consumer endpoints by BytesProcessed/ActiveConnections/RST; capacity planning)

**Interface VPC Endpoint** -> publishes -> **CloudWatch Metrics** (AWS/PrivateLinkEndpoints namespace; 1-minute granularity)

**VPC Endpoint Service** -> publishes -> **CloudWatch Metrics** (AWS/PrivateLinkServices namespace; provider-side visibility)

**Endpoint Policy** -> attached to -> **Interface VPC Endpoint** (IAM-based access control; misconfigured = connection denials)

**Availability Zone Mapping** -> mismatched -> causes -> **cross-AZ data transfer costs** (consumer and provider AZs don't align; cost and latency impact)

**Gateway Load Balancer Endpoint** -> shares -> **same metrics** as **Interface VPC Endpoint** (different use case but identical monitoring)

**PacketDropCount** -> correlates with -> **BytesProcessed** and **Bandwidth Quota** (capacity saturation indicator)

**ResetPacketsReceived** -> correlates with -> **Idle Timeout** and **NLB Target Health** (connection quality indicator)

**NewConnections** -> flat or zero + **Connection State** = Rejected -> indicates -> **Allowed Principal** or **Acceptance Required** issue (authorization problem)

**ActiveConnections** -> steady + **PacketDropCount** = 0 + **ResetPacketsReceived** = 0 -> indicates -> **healthy PrivateLink connectivity** (golden path)

---

## Entities and dimensions (cardinality, safety, dashboard impact)

**EndpointId** (e.g., vpce-0a1b2c3d4e5f6g7h8)
- **Why useful**: Uniquely identifies each interface VPC endpoint; essential for isolating issues to specific endpoints vs systemic problems
- **Cardinality risk**: Medium (1-1000s per account depending on architecture; centralized hub VPC patterns concentrate endpoints)
- **Safe top-N**: 10 for overview KPIs, 25 for deep dive breakdowns
- **Dashboard impact**: Primary group-by dimension for all consumer-side sections (Endpoint Connection Health, Data Transfer & Network Performance, Cost & Usage)

**ServiceName** (e.g., com.amazonaws.vpce.us-east-1.vpce-svc-abc123def456)
- **Why useful**: Identifies the target endpoint service; critical for multi-service environments to isolate failures to specific backends
- **Cardinality risk**: Low-Medium (10-100s typically; most orgs consume <50 PrivateLink services)
- **Safe top-N**: 10 for overview, 20 for deep dive
- **Dashboard impact**: Secondary group-by for consumer dashboards; primary group-by for provider dashboards (Service Performance section)

**ServiceId** (e.g., vpce-svc-abc123def456)
- **Why useful**: Provider-side identifier for endpoint services; used in service provider dashboards
- **Cardinality risk**: Low (1-50 per provider account; most providers expose <10 services)
- **Safe top-N**: 10
- **Dashboard impact**: Primary group-by for provider-side sections (Service Consumer Connections, Backend Target Health)

**AvailabilityZone** (e.g., us-east-1a, us-east-1b)
- **Why useful**: AZ-level isolation for bandwidth quotas (10-100 Gbps per AZ), fault isolation, and cross-AZ cost analysis
- **Cardinality risk**: Very low (2-6 per region; typically 3 AZs used for HA)
- **Safe top-N**: 6 (include all)
- **Dashboard impact**: Critical group-by for Data Transfer & Network Performance (bandwidth saturation is per-AZ), Cost & Usage (cross-AZ data transfer costs)
- **DO NOT group-by**: When aggregating account-wide totals or connection states (AZ dimension not always present in metadata)

**VpcId** (e.g., vpc-0a1b2c3d)
- **Why useful**: Isolates issues to specific VPCs in multi-VPC architectures; hub-spoke patterns benefit from VPC-level breakdowns
- **Cardinality risk**: Medium-High (10-100s in hub-spoke; 1000s in large orgs)
- **Safe top-N**: 10
- **Dashboard impact**: Useful for organizational rollups and multi-tenant providers; less relevant for single-VPC consumers
- **DO NOT group-by**: For per-endpoint deep dives (EndpointId already implies VpcId)

**SubnetId** (e.g., subnet-0a1b2c3d)
- **Why useful**: ENI placement within VPC; useful for diagnosing subnet-specific network ACL or route table issues
- **Cardinality risk**: High (10-100 per VPC; multi-AZ deployments multiply cardinality)
- **Safe top-N**: 5 (only when troubleshooting specific networking issues)
- **Dashboard impact**: Rarely used in standard dashboards; include in deep dive troubleshooting views only
- **DO NOT group-by**: For performance KPIs (explodes cardinality without adding insight; use AvailabilityZone instead)

**Region** (e.g., us-east-1, eu-west-1)
- **Why useful**: Cross-region PrivateLink deployments incur extra data transfer costs ($0.02/GB); region-level breakdowns essential for cost attribution
- **Cardinality risk**: Very low (1-20 regions; typically <5 active)
- **Safe top-N**: 10 (include all active regions)
- **Dashboard impact**: Critical for cross-region connectivity scenarios (separate section in Cost & Usage); not needed for single-region deployments

**AccountId** (AWS account ID)
- **Why useful**: Multi-account environments (consumer accessing provider across accounts) need account-level visibility for chargeback and security auditing
- **Cardinality risk**: Low-Medium (1-100 accounts depending on org size)
- **Safe top-N**: 10
- **Dashboard impact**: Provider-side dashboards (Service Consumer Connections section); less relevant for consumer-only dashboards
- **DO NOT group-by**: When account context is already implicit (single-account consumer deployments)

**ConnectionState** (Available, Pending, Rejected, Failed, Expired)
- **Why useful**: Connection lifecycle tracking; Rejected/Failed states indicate authorization or configuration issues
- **Cardinality risk**: Very low (5 possible states)
- **Safe top-N**: 5 (include all)
- **Dashboard impact**: Essential dimension for Endpoint Connection Health section; use bar/pie charts to show state distribution

**PrincipalArn** (IAM principal ARN)
- **Why useful**: Service provider dashboards use this to track which IAM principals (accounts, roles) are connecting; useful for access auditing and billing breakdowns
- **Cardinality risk**: Medium-High (10-1000s depending on multi-tenant scenarios)
- **Safe top-N**: 10
- **Dashboard impact**: Provider-side Service Consumer Connections section; exclude from consumer dashboards (not visible to consumers)
- **DO NOT group-by**: For consumer-side dashboards (dimension not present in consumer metrics)

**EndpointType** (Interface, GatewayLoadBalancer)
- **Why useful**: Differentiates interface VPC endpoints from Gateway Load Balancer endpoints; architectures mixing both need separate views
- **Cardinality risk**: Very low (2 types)
- **Safe top-N**: 2
- **Dashboard impact**: Use as global filter or section gating (most dashboards focus on Interface endpoints; GWLB endpoints are specialized)

**TargetGroupArn** (NLB target group ARN, provider-side only)
- **Why useful**: Provider-side metric for tracking backend target health per target group; multiple target groups per endpoint service need isolation
- **Cardinality risk**: Low-Medium (1-50 per service)
- **Safe top-N**: 10
- **Dashboard impact**: Backend Target Health section (provider dashboards only); not visible to consumers

**ConsumerEndpointId** (provider-side dimension tracking which consumer endpoints are connecting)
- **Why useful**: Contributor Insights rules use this to rank top consumer endpoints by traffic, connections, or resets; capacity planning and abuse detection
- **Cardinality risk**: Medium-High (1-1000s of consumer endpoints per popular service)
- **Safe top-N**: 10 for Contributor Insights top-N lists
- **Dashboard impact**: Service Consumer Connections section (provider dashboards); shows which consumers drive the most load
- **DO NOT group-by**: For consumer dashboards (not available in consumer-side metrics)

---

## Tsuga field mapping (vendor dimension -> context.* key)

| Vendor/CloudWatch Dimension | Recommended Tsuga Field | Must-Exist vs Optional | Notes |
|---|---|---|---|
| `EndpointId` | `context.endpointid` | Must-exist | Primary consumer-side entity; AWS uses lowercase joined pattern (see ECS/SNS/Transcribe examples) |
| `ServiceName` | `context.servicename` | Must-exist | Target endpoint service; critical for multi-service environments |
| `ServiceId` | `context.serviceid` | Optional | Provider-side entity; may not be present in consumer metrics |
| `Availability Zone` | `context.availabilityzone` OR `context.az` | Must-exist | AWS often abbreviates to `az`; Stage 2 discovery will confirm which |
| `VPC Id` | `context.vpcid` | Optional | Useful for multi-VPC architectures; may not be included in all metrics |
| `Region` | `context.region` | Optional | Only needed for cross-region PrivateLink deployments; Stage 2 will confirm presence |
| `Account Id` | `context.accountid` | Optional | Multi-account scenarios; provider-side visibility |
| `Connection State` | `context.connectionstate` | Optional | May be present in connection-specific metrics; Stage 2 will validate |
| `Endpoint Type` | `context.endpointtype` | Optional | Differentiates Interface vs GatewayLoadBalancer endpoints |
| `Principal Arn` | `context.principalarn` | Optional | Provider-side only; consumer IAM principal identifier |
| `Consumer Endpoint Id` | `context.consumerendpointid` | Optional | Provider-side Contributor Insights; tracks individual consumer endpoints |
| `Target Group Arn` | `context.targetgrouparn` | Optional | Provider-side NLB target group tracking |

**Fallback strategy for Stage 2 discovery:**
- If `context.endpointid` is not found, check `context.endpoint_id` (underscore-separated)
- If `context.servicename` is not found, check `context.service_name`
- AWS PrivateLink metrics may use dot-separated namespaces (e.g., `aws.privatelink.endpoint.id`) — Stage 2 will validate actual naming

**Context fields from .env (assumed present):**
- `context.env` — environment tag (prod, staging)
- `context.team` — owning team tag

---

## Confirmed by sources
- Interface VPC Endpoint and VPC Endpoint Service are the core PrivateLink entities ([AWS PrivateLink concepts](https://docs.aws.amazon.com/vpc/latest/privatelink/concepts.html))
- Connection states: Available, Pending, Rejected, Expired, Failed ([AWS PrivateLink service config](https://docs.aws.amazon.com/vpc/latest/privatelink/configure-endpoint-service.html))
- 350-second idle timeout for TCP connections ([AWS re:Post network performance](https://repost.aws/knowledge-center/vpc-troubleshoot-network-performance-privatelink))
- 10 Gbps baseline bandwidth, auto-scales to 100 Gbps per AZ ([same source](https://repost.aws/knowledge-center/vpc-troubleshoot-network-performance-privatelink))
- CloudWatch metrics published in AWS/PrivateLinkEndpoints and AWS/PrivateLinkServices namespaces ([CloudWatch metrics docs](https://docs.aws.amazon.com/vpc/latest/privatelink/privatelink-cloudwatch-metrics.html))
- Pricing: $0.01/hour per interface endpoint, $0.01-$0.004/GB data processing (tiered), $0.02/GB cross-region ([AWS PrivateLink pricing](https://aws.amazon.com/privatelink/pricing/))
- Contributor Insights integration for ranking top consumer endpoints ([AWS blog](https://aws.amazon.com/blogs/networking-and-content-delivery/gain-usage-insights-with-amazon-cloudwatch-metrics-for-aws-privatelink/))

## Best-practice inference
- Tsuga field naming inferred from AWS ECS/SNS/Transcribe patterns (all-lowercase joined names like `context.servicename`)
- Multi-AZ deployment recommendation follows AWS Well-Architected reliability best practices
- Top-N limits (10 for overview, 25 for deep dive) follow Tsuga cardinality safety patterns from previous integrations
- "DO NOT group-by" guidance inferred from high-cardinality explosion risks (SubnetId, PrincipalArn in multi-tenant scenarios)
- Cross-AZ cost analysis importance inferred from AWS data transfer pricing model (same-AZ = free, cross-AZ = $0.01/GB)


---

# AWS PrivateLink — Golden Signals

## Traffic (volume of work)

**What it means for PrivateLink**
Traffic represents the volume of private network connectivity: how many new connections consumers are establishing, how many concurrent connections are active, and how much data is flowing through endpoint network interfaces. For PrivateLink, traffic is measured at three levels: connection establishment rate (NewConnections), sustained connection load (ActiveConnections), and data volume (BytesProcessed). Unlike public internet traffic, PrivateLink traffic remains within AWS's private network backbone.

**Typical causes when traffic degrades**
- **NewConnections drops to zero**: Connection requests rejected by service provider (manual acceptance required but not granted), allowed principal list missing consumer account, endpoint policy denying access, security group blocking traffic
- **ActiveConnections drops unexpectedly**: Idle timeout exceeded (350s without keepalive), application closing connections due to backend errors, NLB targets becoming unhealthy, cross-region PrivateLink path failures
- **BytesProcessed fluctuates or drops**: Client application throttling, backend service capacity limits, NLB target auto-scaling lag, cross-AZ or cross-region bandwidth constraints

**Best telemetry sources representing traffic**
- **Primary**: CloudWatch metrics in AWS/PrivateLinkEndpoints namespace: `NewConnections` (rate), `ActiveConnections` (gauge), `BytesProcessed` (counter)
- **Secondary (provider-side)**: AWS/PrivateLinkServices namespace: same metrics from service provider perspective
- **Tertiary**: VPC Flow Logs for endpoint ENIs (granular packet-level visibility when CloudWatch metrics insufficient)
- **Contributor Insights**: Ranks consumer endpoints by BytesProcessed, ActiveConnections, NewConnections for capacity planning

**What people page on (symptom-based)**
- NewConnections flatlined while application attempting connections → **service unreachable; immediate escalation**
- ActiveConnections dropping >50% within 5 minutes without planned changes → **mass disconnection event; investigate backend health and idle timeout issues**
- BytesProcessed sustained near bandwidth quota (10 Gbps baseline) with PacketDropCount rising → **capacity saturation; scale to more AZs or investigate traffic spike**

**Section questions for dashboards**
1. **Are consumers establishing new connections successfully?** (NewConnections rate, connection state distribution, rejection/failure counts)
2. **How many concurrent connections are active across endpoints?** (ActiveConnections per endpoint/service, trend over time, top endpoints by connection count)
3. **What is the data transfer volume and bandwidth utilization?** (BytesProcessed rate, per-AZ bandwidth quotas, cross-region vs same-region breakdowns)

---

## Errors (rate of failing requests)

**What it means for PrivateLink**
Errors in PrivateLink manifest as connection establishment failures (rejected/failed/expired connection requests), TCP reset packets indicating abrupt connection terminations, and packet drops caused by network congestion or configuration issues. Unlike application-layer errors (HTTP 4xx/5xx), PrivateLink errors occur at the network layer (Layer 3/4) before traffic reaches the application. A single PrivateLink error can cause cascading application failures.

**Typical causes when error rates increase**
- **Connection rejections (state = Rejected)**: Service provider explicitly rejected connection request, acceptance required but not granted within timeout, endpoint policy denying principal
- **Connection failures (state = Failed)**: Subnet route table missing local route, security group blocking port, cross-region connectivity not enabled for service, DNS resolution failures for private DNS
- **RST resets (ResetPacketsReceived spiking)**: Idle timeout exceeded (350s) without TCP keepalive, NLB target health checks failing and terminating active connections, MTU mismatch causing fragmentation failures, application-layer connection closures propagating as RST
- **Packet drops (PacketDropCount elevated)**: Bandwidth quota exceeded (10 Gbps per AZ), ENI network interface limits reached, MTU misconfiguration, consumer or provider network congestion

**Best telemetry sources representing errors**
- **Primary**: CloudWatch metrics: `PacketDropCount` (sum), `ResetPacketsReceived` (sum), connection state metrics (Rejected/Failed counts if available)
- **Secondary**: VPC Flow Logs filtered for REJECT action, ENI statistics showing drops
- **Tertiary**: NLB target health status (provider-side; unhealthy targets cause downstream resets)
- **Application logs**: Connection timeouts, "connection refused", DNS resolution failures (supplement CloudWatch metrics)

**What people page on (symptom-based)**
- ResetPacketsReceived sustained >100/min per endpoint → **active connection instability; investigate idle timeout or backend health**
- PacketDropCount >1% of BytesProcessed → **network congestion or bandwidth saturation; scale endpoints or reduce traffic**
- Connection state = Rejected or Failed for >5 minutes → **authorization or configuration issue; immediate remediation needed**
- Sudden spike in all error metrics simultaneously → **systemic PrivateLink or NLB outage; escalate to AWS support**

**Section questions for dashboards**
1. **Are endpoint connections being rejected or failing to establish?** (connection state distribution, rejection counts, failure reasons)
2. **Are active connections experiencing TCP resets?** (ResetPacketsReceived rate, correlation with idle timeout, NLB target health)
3. **Is the network dropping packets due to congestion or misconfiguration?** (PacketDropCount rate, bandwidth quota utilization, MTU issues)

---

## Latency (time to complete work)

**What it means for PrivateLink**
PrivateLink itself does not publish end-to-end latency metrics (application request/response time). However, connection establishment latency (time from endpoint creation to Available state), DNS resolution latency (private DNS lookups), and cross-region latency (data plane delay when crossing region boundaries) all impact perceived performance. Most latency visibility comes from application-layer instrumentation or CloudWatch Network Synthetic Monitors.

**Typical causes when latency increases**
- **Connection establishment delay**: Manual acceptance required (connection sits in Pending state until provider acts), cross-region connectivity adding inter-region latency (~50-150ms depending on regions), slow NLB target health check responses
- **DNS resolution delay**: Private hosted zone misconfiguration, Route 53 Resolver endpoint saturation, split-horizon DNS fallback to public DNS causing extra hops
- **Data plane latency**: Cross-region PrivateLink adding inter-region transit time, cross-AZ traffic (intra-region but cross-AZ ~1-2ms overhead), MTU fragmentation causing retransmissions
- **Backend service latency**: NLB target processing time (not a PrivateLink issue but visible to consumers as increased end-to-end latency)

**Best telemetry sources representing latency**
- **Primary (application-layer)**: Application request tracing (X-Ray, OpenTelemetry), application logs with request timestamps
- **Secondary**: CloudWatch Network Synthetic Monitor (proactive synthetic testing of PrivateLink paths, cross-region latency measurements)
- **Tertiary**: VPC Flow Logs with flow duration analysis (rough proxy for connection lifetime)
- **Indirect**: NewConnections trend (slow connection establishment = latency issue)

**What people page on (symptom-based)**
- Application request latency (measured in application) increased by >2x correlated with PrivateLink metrics (PacketDropCount, ResetPacketsReceived) → **PrivateLink network issue impacting app performance**
- DNS resolution timeouts or >1s latency for private DNS-enabled endpoints → **Route 53 or split-horizon DNS misconfiguration**
- Cross-region PrivateLink showing sustained >200ms latency (expected is 50-150ms) → **inter-region path degradation; validate with Network Synthetic Monitor**

**Section questions for dashboards**
1. **How long does it take for endpoint connections to become Available?** (time from Pending to Available state, manual acceptance delays)
2. **Is DNS resolution for private DNS-enabled endpoints performing within SLA?** (DNS query latency from Route 53 metrics, failure rates)
3. **What is the end-to-end latency for cross-region PrivateLink connections?** (Network Synthetic Monitor results, application-layer latency breakdowns)

---

## Saturation (resource capacity limits)

**What it means for PrivateLink**
Saturation occurs when PrivateLink endpoints approach or exceed capacity limits: bandwidth quotas (10 Gbps baseline per AZ, auto-scales to 100 Gbps), connection count limits (ENI connection tracking limits), or provider-side NLB target capacity. Unlike traditional networking where saturation causes complete failures, PrivateLink scales elastically in many dimensions but has hard limits in others. Saturation manifests as PacketDropCount increases, NewConnections throttling, or backend target exhaustion.

**Typical causes when saturation increases**
- **Bandwidth saturation per AZ**: Single-AZ endpoint deployment handling >10 Gbps, burst traffic exceeding auto-scaling rate (10→100 Gbps takes seconds), sustained multi-region traffic concentrating on one AZ
- **Connection count saturation**: ENI connection tracking limits (~55k concurrent connections per ENI), single endpoint handling more connections than intended (should distribute across AZs)
- **Provider-side target saturation**: NLB targets at CPU/memory/network capacity, target count insufficient for connection volume, target auto-scaling lag during traffic spikes
- **Cross-region bandwidth saturation**: Inter-region PrivateLink bandwidth limits (not well-documented; assumed to scale similarly to intra-region)

**Best telemetry sources representing saturation**
- **Primary**: CloudWatch metrics: `PacketDropCount` (direct saturation indicator), `BytesProcessed` trend approaching bandwidth quotas, `ActiveConnections` approaching ENI limits
- **Secondary**: NLB target metrics (provider-side): `TargetConnectionErrorCount`, `UnHealthyHostCount`, `ProcessedBytes` per target
- **Tertiary**: VPC Flow Logs showing ENI-level connection counts, AWS Service Quotas API for PrivateLink limits
- **Contributor Insights**: Identifies which consumer endpoints or services are consuming the most bandwidth/connections (hotspot detection)

**What people page on (symptom-based)**
- PacketDropCount sustained >0 correlated with BytesProcessed approaching 10 Gbps per AZ → **bandwidth saturation; add more AZs or request quota increase**
- ActiveConnections per endpoint approaching ~50k with NewConnections dropping → **ENI connection tracking limit; distribute load across more endpoints**
- Provider-side NLB UnHealthyHostCount increasing with consumer-side PacketDropCount/ResetPacketsReceived rising → **backend target capacity exhaustion**
- BytesProcessed growing 10x week-over-week without endpoint scaling → **proactive capacity planning needed before saturation hits**

**Section questions for dashboards**
1. **Are endpoints approaching bandwidth capacity limits?** (BytesProcessed rate per AZ vs 10 Gbps baseline, PacketDropCount as saturation indicator)
2. **Is connection count approaching ENI connection tracking limits?** (ActiveConnections per endpoint, trend toward ~50k threshold)
3. **Are backend NLB targets saturated?** (provider-side: target count, connection error rate, unhealthy host count)

---

## Confirmed by sources
- CloudWatch metrics: NewConnections, ActiveConnections, BytesProcessed, PacketDropCount, ResetPacketsReceived published in 1-minute intervals ([AWS CloudWatch metrics docs](https://docs.aws.amazon.com/vpc/latest/privatelink/privatelink-cloudwatch-metrics.html))
- Bandwidth: 10 Gbps baseline per AZ, auto-scales to 100 Gbps ([AWS re:Post](https://repost.aws/knowledge-center/vpc-troubleshoot-network-performance-privatelink))
- Idle timeout: 350 seconds for TCP connections through PrivateLink endpoints ([same source](https://repost.aws/knowledge-center/vpc-troubleshoot-network-performance-privatelink))
- Connection states: Available, Pending, Rejected, Expired, Failed ([AWS service config docs](https://docs.aws.amazon.com/vpc/latest/privatelink/configure-endpoint-service.html))
- ENI connection tracking limits: ~55k concurrent connections per ENI ([inferred from general ENI limits; not PrivateLink-specific documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html))
- Contributor Insights for PrivateLink ranking top endpoints by BytesProcessed, ActiveConnections, NewConnections, ResetPacketsReceived ([AWS blog](https://aws.amazon.com/blogs/networking-and-content-delivery/gain-usage-insights-with-amazon-cloudwatch-metrics-for-aws-privatelink/))

## Best-practice inference
- Latency section synthesized from indirect sources (no native PrivateLink latency metrics exist; CloudWatch Network Synthetic Monitor is a separate service)
- ENI connection tracking limit (~55k) inferred from general AWS ENI documentation, not PrivateLink-specific (Stage 2 discovery should note this as "inferred")
- Cross-region bandwidth saturation behavior inferred from general AWS networking patterns (no explicit PrivateLink cross-region bandwidth limits documented)
- Paging thresholds (>100 RST/min, >1% packet drop rate, >50% ActiveConnections drop) inferred from operational experience and AWS re:Post troubleshooting guidance
- Golden signal section question mapping follows standard observability practices (traffic → volume questions, errors → failure mode questions, latency → timing questions, saturation → capacity questions)


---

# AWS PrivateLink — Section Notes & Playbooks

---

## Part 1: Overview Mission Note

```markdown
**AWS PrivateLink — Private Connectivity Monitoring**

Private network connectivity between VPCs, AWS services, and on-premises networks without internet exposure. Monitors interface VPC endpoints (consumers) and endpoint services (providers) using CloudWatch metrics.

**Monitoring scope**: All VPC endpoints and endpoint services in this account reporting CloudWatch metrics (AWS/PrivateLinkEndpoints and AWS/PrivateLinkServices namespaces). Does not cover gateway endpoints, VPC peering, or Transit Gateway.

**Learn more:**
- [CloudWatch metrics for PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/privatelink-cloudwatch-metrics.html)
- [PrivateLink concepts](https://docs.aws.amazon.com/vpc/latest/privatelink/concepts.html)
- [Deep Dive Dashboard](#) (link to deep dive dashboard once created)
```

---

## Part 2: Section Explanation Notes

### Endpoint Connection Health

#### So what?

Healthy PrivateLink deployments maintain **stable Active Connections with minimal New Connection churn**. Connection-pooled applications (databases, message queues) typically show **NewConnections < 1 conn/s** once pools are established, with **ActiveConnections steady at 10-1000**. Short-lived connection applications (HTTP APIs, serverless) show **higher NewConnections (10-100 conn/s)** with **lower ActiveConnections (1-100)**.

**When to worry**: NewConnections drops to **zero while applications attempt connections** = authorization failure (connection state Rejected), security group blocking traffic, or DNS resolution failure. ActiveConnections drops **>50% within 5 minutes** without planned changes = mass disconnection event (idle timeout exceeded, backend health failures, cross-region path degradation).

**Watch out**: Connection state = **Pending for >1 hour** likely means the service provider requires manual acceptance (`acceptance_required = true`) but hasn't approved yet—this is operational delay, not failure. NewConnections = 0 with high stable ActiveConnections is **healthy** for connection-pooled apps, not a problem.

#### Now what?

**If NewConnections drops to zero unexpectedly**:
1. Check **Active Connections (trend)** — if also dropping to zero, it's full connectivity loss; if stable, connection pools are saturated (no new connections needed)
2. Check application logs for "connection refused" or DNS resolution errors
3. Verify endpoint ENI security group allows traffic on the listener port
4. Check if endpoint connection state = Rejected/Failed (provider authorization issue)

**If ActiveConnections drops suddenly**:
1. Check **RST Resets by Endpoint** — if spiking, idle timeout or backend health failure
2. Check **Backend Health Ratio** (provider-side) — if <100%, unhealthy NLB targets terminating connections
3. Correlate with application deployment windows (graceful shutdown causes FIN, forced termination causes RST)
4. Check VPC Flow Logs for REJECT actions (security group denials)

---

### Data Transfer & Network Performance

#### So what?

Healthy PrivateLink data transfer shows **zero PacketDropCount and minimal ResetPacketsReceived (<1 RST/s)**. **BytesProcessed** grows with application traffic; baseline varies widely (1-100 MB/s typical, 1+ GB/s for bulk data).

**Bandwidth per AZ**: PrivateLink starts at **10 Gbps (1250 MB/s) per AZ** and auto-scales to 100 Gbps. **Utilization >80%** = approaching saturation; PacketDropCount will rise. **Utilization <50%** = healthy headroom. **Always group by AvailabilityZone** for bandwidth analysis; per-AZ quotas mean aggregating across AZs hides hotspots.

**When to worry**: **Any sustained PacketDropCount >0** is actionable (MTU mismatch, bandwidth saturation, network congestion). **ResetPacketsReceived >100 RST/s** per endpoint = active connection instability (idle timeout without TCP keepalive, backend failures, application errors). **Bandwidth Utilization per AZ >80%** sustained = add more AZs or reduce traffic.

**Watch out**: **RST spikes during deployments** (10-100 RST/s for 1-2 minutes) are **normal** (forced container/instance termination sends RST). Only sustained RST elevation outside deploy windows is actionable. **PacketDropCount 1-2 drops/hour** during auto-scaling (PrivateLink scaling 10→100 Gbps) is **transient**, not a problem.

#### Now what?

**If PacketDropCount sustained >0**:
1. Check **Bandwidth Utilization per AZ** — if >80%, bandwidth saturation; add more AZs or scale endpoints
2. Check **Packet Drops by Availability Zone** — identify which AZ is saturated (single-AZ hotspot common)
3. Check **Data Throughput by Endpoint** — identify which endpoints drive the most traffic
4. Verify MTU settings (PrivateLink caps at 1500 bytes; jumbo frames not supported)

**If ResetPacketsReceived sustained >10 RST/s**:
1. Check **Backend Health Ratio** (provider-side) — if <100%, NLB target failures causing RSTs
2. Check **Average Bytes per Connection** — if spiking, long-running transfers hitting idle timeout (350s)
3. Verify TCP keepalive enabled in application (required for connections idle >350s)
4. Correlate with **NLB Target Connection Errors** (provider-side) — backend capacity exhaustion

**If Bandwidth Utilization per AZ approaching 80%**:
1. Add endpoint network interfaces in more Availability Zones (distribute load)
2. Check **Data Throughput by Endpoint (top 10)** — identify traffic hotspots
3. Consider endpoint count scaling (more endpoints = more aggregate bandwidth)
4. Check if cross-region traffic can be localized (inter-region adds latency and cost)

---

### Backend Target Health (provider-side)

#### So what?

**Provider-side only**: Service consumers cannot see NLB metrics. This section monitors the health of backend targets behind the Network Load Balancer backing your PrivateLink endpoint service.

**Healthy baseline**: **100% Backend Health Ratio** (all targets healthy), **zero NLB Target Connection Errors**. Temporary **UnHealthyHostCount 1-2 during target launches** (EC2 starting, containers initializing) is **normal**; health checks fail until application fully starts (30-60s grace period).

**When to worry**: **Backend Health Ratio <50%** sustained >5 minutes = critical capacity impact; consumers will see increased PacketDropCount and ResetPacketsReceived. **HealthyHostCount = 0** = full service outage for all consumers. **NLB Connection Error Rate >1 error/s** = backend capacity exhaustion (targets refusing connections, port mismatches, target crashes).

**Watch out**: **HealthyHostCount = 0 with UnHealthyHostCount = 0** means **no registered targets** (configuration issue, not health failure). Check if target auto-scaling terminated all instances or targets were manually deregistered. **UnHealthyHostCount spikes during deployments** are **expected** (old targets drain and fail health checks before new targets pass).

#### Now what?

**If Backend Health Ratio drops <80%**:
1. Check **Unhealthy Targets by Endpoint Service** — identify which service is degraded
2. Check application logs on unhealthy targets (port not listening, health check path failing)
3. Verify NLB health check configuration (correct port, path, interval, timeout)
4. Check target auto-scaling (insufficient capacity, launch failures)

**If NLB Connection Error Rate >1 error/s**:
1. Check **Healthy Targets (trend)** — if dropping, backend service crashes or capacity exhaustion
2. Check target CPU/memory/network utilization (backend resource saturation)
3. Verify listener port matches target application port (port mismatch = connection errors)
4. Correlate with consumer-side **RST Resets by Endpoint** — backend errors propagate as RSTs to consumers

**If HealthyHostCount = 0**:
1. Check if target group has any registered targets (DescribeTargetHealth API)
2. Check target auto-scaling group (desired capacity, launch failures, AZ mismatches)
3. Check target security group (health check traffic blocked)
4. Check application logs on targets (crash loops, failed to bind to port)

---

### Cost & Usage

#### So what?

PrivateLink costs have **three components**: **hourly endpoint charge** ($0.01/hour per interface endpoint, not metered in CloudWatch), **data processing charge** (tiered: $0.01/GB tier 1, $0.006/GB tier 2, $0.004/GB tier 3), and **cross-region data transfer** ($0.02/GB additional for inter-region traffic).

**Typical baselines**: Intra-region deployments processing **1 TB/month = ~$10/month** data processing (tier 1) + **$7.20/month** endpoint hourly charge (1 endpoint, 720 hours). Cross-region adds **$20/month** per TB transferred. High-throughput scenarios (10+ TB/month) benefit from tiered pricing (drop to $0.006 then $0.004/GB).

**When to worry**: **Data cost increasing >50% week-over-week** without known traffic growth = unexpected traffic spike or runaway batch job. **Cross-region cost >intra-region cost** = architecture inefficiency (consider replicating services to consumer regions).

**Watch out**: **Cost doubling during backup windows or batch jobs is expected** (PrivateLink charges per GB; overnight ETL or database replication legitimately increases costs). **Baseline during business hours**, not peak windows. **Dashboard shows tier 1 rate ($0.01/GB) only**; actual billing uses tiered rates (tier 2/3 cheaper at scale).

#### Now what?

**If data processing cost increasing unexpectedly**:
1. Check **Data Processing Cost by Endpoint (top 10)** — identify which endpoints drive cost growth
2. Check **Data Throughput by Endpoint** — correlate cost with traffic volume
3. Review application changes (new batch jobs, increased replication, accidental data loops)
4. Check **Total Data Processed (GB/hour)** trend — identify when growth started

**If cross-region cost is high**:
1. Check **Data Processed by Region** — identify which regions consume the most cross-region bandwidth
2. Evaluate architecture: can services be replicated to consumer regions (eliminate cross-region transfer)?
3. Check if cross-region traffic is read-heavy (consider regional read replicas)
4. Validate cross-region is intentional (not misconfigured endpoint pointing to wrong region)

**For capacity planning**:
1. Hourly endpoint charge = **$0.01/hour * endpoint count * 720 hours/month**
2. Data processing cost = **BytesProcessed (GB/month) * tiered rate** (tier 1: $0.01, tier 2: $0.006, tier 3: $0.004)
3. Cross-region cost = **BytesProcessed cross-region (GB/month) * $0.02**
4. Use **Data Throughput (MB/s)** * 2.628 million = GB/month (30 days) for monthly projection

---

## Part 3: Cause-Effect Triage Chains

### Connection Health Chains

1. **If Active Connections (current) drops to zero** → check **Active Connections (trend)** for gradual vs sudden drop → likely causes: mass idle timeout expiration (no TCP keepalive), NLB target health failure (provider-side), cross-region path failure → next action: check RST Resets (rate) for spike; verify backend health ratio (provider-side); check application logs for connection errors. (Confirmed: idle timeout and NLB health documented)

2. **If New Connections (rate) drops to zero while ActiveConnections stable** → this is **healthy** (connection pools established, no new connections needed) → likely causes: connection-pooled application (database, message queue) reached steady state → next action: no action needed unless applications report connection failures. (Inference: connection pool behavior)

3. **If New Connections (rate) drops to zero AND ActiveConnections drops to zero** → check application logs for "connection refused" or DNS errors → likely causes: endpoint connection state = Rejected/Failed (authorization issue), security group blocking traffic, DNS resolution failure → next action: verify endpoint state in VPC console; check security group rules; test DNS resolution (nslookup). (Confirmed: connection states documented)

4. **If Connection Churn Ratio >1.0 sustained** → check **New Connections by Endpoint (top 10)** for which endpoints have high churn → likely causes: short-lived connection pattern (Lambda, serverless), connection pool misconfiguration (max idle time too low), application restart loops → next action: review application connection pooling settings; check application logs for errors causing reconnects. (Inference: connection pool patterns)

5. **If Active Connections by Endpoint shows one endpoint >> others** → check if this is expected traffic distribution OR hotspot → likely causes: application routing imbalance (all traffic to one service), service discovery not load-balancing, client-side caching pointing to single endpoint → next action: verify application load balancing configuration; check service discovery health checks. (Inference: traffic distribution patterns)

### Data Transfer & Performance Chains

6. **If Packet Drops (rate) >0 sustained** → check **Bandwidth Utilization per AZ** for saturation (>80%) → likely causes: bandwidth quota exceeded (10 Gbps per AZ), MTU mismatch (jumbo frames not supported), network congestion → next action: check Packet Drops by Availability Zone to identify saturated AZ; add endpoints in more AZs; verify MTU ≤1500 bytes. (Confirmed: bandwidth limits and MTU cap documented)

7. **If RST Resets (rate) spikes >100 RST/s** → check timing correlation with deployments OR sustained elevation → likely causes: idle timeout exceeded (350s; no TCP keepalive), NLB target health failure (provider-side), application-layer connection closures → next action: verify TCP keepalive enabled for long-lived connections; check Backend Health Ratio (provider-side); check application error logs. (Confirmed: idle timeout documented)

8. **If Bandwidth Utilization per AZ >80%** → check **Packet Drops (rate)** for correlation (drops occur when bandwidth saturated) → likely causes: traffic spike, insufficient AZ distribution, single endpoint handling bulk transfers → next action: add endpoint ENIs in more AZs; check Data Throughput by Endpoint (top 10) to identify traffic sources; scale endpoint count. (Confirmed: bandwidth limits documented)

9. **If Data Throughput (MB/s) drops >50% within 5 minutes** → check **Active Connections (trend)** for drop (connection loss) → likely causes: backend service outage (NLB targets unhealthy), network path failure, application throttling → next action: check Backend Health Ratio (provider-side); check RST Resets for spike; review application logs. (Mixed: throughput drop + connection correlation inferred)

10. **If Average Bytes per Connection spikes >10 MB/s per conn** → this indicates bulk data transfers OR streaming → likely causes: backup jobs, database replication, large file transfers → next action: verify this is expected workload (not runaway data loop); check Data Processing Cost for impact; ensure bandwidth headroom exists. (Inference: throughput per connection patterns)

11. **If Packet Drops by Availability Zone shows one AZ >> others** → check **Bandwidth Utilization per AZ** for that AZ (likely >80%) → likely causes: single-AZ endpoint deployment, application client affinity to one AZ, cross-AZ traffic routing inefficiency → next action: add endpoint ENI in additional AZs; verify client load balancing across AZs; check VPC route tables. (Inference: per-AZ saturation patterns)

12. **If RST Resets by Endpoint correlates with high Active Connections** → likely idle timeout expiration (350s) on long-lived connections → likely causes: application not sending TCP keepalive, WebSocket/streaming connections exceeding idle timeout, backend processing latency >350s → next action: enable TCP keepalive in application; check Average Bytes per Connection (long-running transfers at risk); reduce backend processing time. (Confirmed: idle timeout documented)

### Backend Health Chains (provider-side)

13. **If Backend Health Ratio drops <80%** → check **Unhealthy Targets by Endpoint Service** to identify which service degraded → likely causes: application crash, health check path failing, target security group blocking health checks, auto-scaling insufficient capacity → next action: check application logs on unhealthy targets; verify NLB health check config (port, path, interval); check target auto-scaling desired capacity. (Confirmed: NLB health checks documented)

14. **If Healthy Targets (current) = 0 AND Unhealthy Targets = 0** → this is **configuration issue**, not health failure (no registered targets) → likely causes: auto-scaling terminated all instances, targets manually deregistered, target group misconfigured → next action: check target group registered targets (DescribeTargetHealth); check auto-scaling group desired capacity; verify NLB target group association. (Inference: target registration patterns)

15. **If NLB Target Connection Errors (rate) >1 error/s** → check **Healthy Targets (trend)** for drop (backend capacity exhaustion) → likely causes: target CPU/memory saturation, application refusing connections (backlog full), listener port mismatch with target port → next action: check target resource utilization (CloudWatch metrics for EC2/ECS); verify listener port = target application port; check application logs for connection rejections. (Confirmed: NLB connection errors documented)

16. **If Unhealthy Targets by Endpoint Service spikes during deployment** → this is **expected** (old targets draining, new targets launching) → likely causes: rolling deployment, auto-scaling replacing instances, health check grace period not expired → next action: no immediate action; monitor for return to 0 unhealthy within 5 minutes; if sustained, check new target launch failures. (Inference: deployment patterns)

17. **If Backend Health Ratio drops AND consumer-side RST Resets spike** → backend health failures propagating to consumers → likely causes: NLB target health checks failing, backend service crashes, database connection pool exhaustion → next action: prioritize backend remediation (unhealthy targets); check target application logs; verify database/dependency health; check NLB TargetConnectionErrorCount correlation. (Mixed: backend-to-consumer correlation inferred from networking principles)

### Cost & Usage Chains

18. **If Data Processing Cost (USD/hour) increasing week-over-week** → check **Data Processing Cost by Endpoint (top 10)** to identify cost drivers → likely causes: traffic growth (legitimate), new batch jobs, application data loop (bug), increased replication → next action: check Data Throughput by Endpoint for traffic growth correlation; review application changes; check for runaway processes. (Confirmed: pricing structure documented)

19. **If Total Data Processed (GB/hour) spikes overnight** → check timing (backup window, batch job schedule) → likely causes: scheduled backups, ETL jobs, database replication, bulk data sync → next action: verify this is expected workload (not anomaly); check if jobs can be optimized; ensure bandwidth headroom during peak. (Inference: batch job patterns)

20. **If Data Processed by Region shows high cross-region traffic** → calculate cost impact ($0.02/GB inter-region surcharge) → likely causes: cross-region service consumption (intentional), service not replicated to consumer regions, misconfigured endpoint pointing to wrong region → next action: evaluate architecture for regional service replication; check if cross-region is required (regulatory, DR) vs inefficiency; validate endpoint region configuration. (Confirmed: cross-region pricing documented)

---

## Part 4: Operational Playbooks

### Playbook 1: Connection Establishment Failure (NewConnections = 0)

**Trigger**: **New Connections (rate)** drops to zero AND **Active Connections (current)** also drops to zero OR approaching zero, AND application logs show connection timeouts or "connection refused" errors.

**Decision rule**: If sustained >2 minutes outside planned maintenance windows, escalate immediately (user-facing impact).

**Steps**:
1. Check **Active Connections by Endpoint (top 10)** — identify which endpoint(s) affected (all or subset)
2. Check endpoint connection state in VPC console (DescribeVpcEndpoints) — look for Rejected, Failed, or Expired states
3. If state = **Rejected**: Service provider rejected connection request → contact provider to add your AWS account/IAM principal to allowed principals list
4. If state = **Failed**: Configuration issue → check endpoint ENI security group (must allow listener port), check subnet route table (must have local VPC route), verify DNS resolution
5. Check VPC Flow Logs filtered to endpoint ENI IPs — look for REJECT action (security group denial) or no flow entries (traffic not reaching endpoint)
6. Test DNS resolution manually (nslookup or dig) — verify private DNS resolves to endpoint ENI private IPs (if private DNS enabled)
7. Check application logs for specific error messages ("connection refused" vs "timeout" vs "no route to host") — each indicates different failure point
8. If all endpoints affected simultaneously: Check AWS Health Dashboard for PrivateLink service events in your region

**Likely causes**:
- Endpoint connection not accepted by provider (manual acceptance required, but not yet approved)
- Consumer AWS account or IAM principal not in endpoint service allowed principals list (authorization failure)
- Endpoint ENI security group blocking traffic on listener port
- DNS resolution failure (private hosted zone not associated with VPC, or VPC DNS settings disabled)
- Subnet route table missing local VPC route (rare but possible if manually modified)

**Next actions**:
- If authorization issue: Contact service provider to request access
- If security group: Update inbound rules to allow traffic from application subnets on listener port
- If DNS: Verify private hosted zone VPC association; check VPC enableDnsHostnames and enableDnsSupport settings
- If configuration: Recreate endpoint with correct subnet, security group, and VPC settings

**Label**: **Confirmed** (connection states, security group, DNS patterns documented in AWS PrivateLink troubleshooting guide)

---

### Playbook 2: Bandwidth Saturation and Packet Drops

**Trigger**: **Packet Drops (rate)** sustained >1 drop/s AND **Bandwidth Utilization per AZ** >80% for the same Availability Zone(s).

**Decision rule**: If sustained >5 minutes and affecting production traffic (user-facing latency or errors), escalate to add capacity immediately.

**Steps**:
1. Check **Bandwidth Utilization per AZ** — identify which Availability Zone(s) are saturated (>80% of 10 Gbps baseline)
2. Check **Packet Drops by Availability Zone** — confirm packet drops correlate with saturated AZ (not all AZs)
3. Check **Data Throughput by Endpoint (top 10)** — identify which endpoint(s) are driving the most traffic to the saturated AZ
4. Check if endpoint is deployed in multiple AZs — single-AZ deployment = hotspot; multi-AZ = traffic imbalance
5. If single-AZ: Create endpoint network interfaces in additional Availability Zones (add AZs to existing endpoint) → distributes load across more 10 Gbps quotas
6. If multi-AZ but one AZ saturated: Check application client load balancing — clients may have affinity to one AZ due to DNS caching or client-side routing
7. Check **Data Throughput (MB/s)** trend — is this a sustained traffic increase (need permanent capacity) or transient spike (wait for auto-scaling to 100 Gbps)?
8. Monitor **Packet Drops (rate)** after adding AZs — should drop to zero within 2-5 minutes as traffic redistributes

**Likely causes**:
- Single-AZ endpoint deployment handling traffic that exceeds 10 Gbps baseline
- Multi-AZ endpoint but client load balancing inefficient (all clients connect to one AZ)
- Burst traffic spike exceeding 10 Gbps before PrivateLink auto-scales to 100 Gbps (transient drops during scaling)
- Sustained traffic growth approaching or exceeding 10 Gbps per AZ

**Next actions**:
- Add endpoint ENIs in more Availability Zones (distribute load across more 10 Gbps quotas)
- Verify application clients use DNS with short TTLs (5-60s) to redistribute across AZ ENIs
- Check if traffic can be reduced (caching, compression, rate limiting) or scheduled (batch jobs during off-peak)
- For sustained >80 Gbps aggregate: Contact AWS support to confirm 100 Gbps auto-scaling is functioning

**Label**: **Confirmed** (10 Gbps baseline, 100 Gbps auto-scale limit, packet drops due to bandwidth saturation documented)

---

### Playbook 3: Active Connection Instability (High RST Reset Rate)

**Trigger**: **RST Resets (rate)** sustained >100 RST/s per endpoint, AND not correlated with known deployment windows (application restarts, auto-scaling events).

**Decision rule**: If causing user-facing errors (connection resets mid-request) or sustained >10 minutes, investigate immediately.

**Steps**:
1. Check **RST Resets by Endpoint (top 10)** — identify which endpoint(s) affected (all or specific ones)
2. Check timing pattern — are RST spikes occurring every ~6 minutes (350 seconds)? → indicates idle timeout expiration
3. If idle timeout pattern: Check application connection lifecycle — long-lived connections (WebSocket, streaming, database) require TCP keepalive to prevent timeout
4. Check **Backend Health Ratio** (provider-side if available) — if <100%, unhealthy NLB targets cause connection terminations that propagate as RSTs to consumers
5. Check **Average Bytes per Connection** — if high (>5 MB/s per conn), long-running bulk transfers may exceed idle timeout (350s with no data = timeout)
6. Check **NLB Target Connection Errors (rate)** (provider-side) — if >1 error/s, backend capacity exhaustion or application refusing connections
7. Check application logs for error messages during RST spikes — "connection reset by peer", "broken pipe", "EOF" all indicate RST
8. Check VPC Flow Logs for TCP flag analysis — look for RST flag (0x04) to confirm resets vs graceful FIN closures

**Likely causes**:
- Idle timeout (350s) exceeded on long-lived connections without TCP keepalive packets sent
- Backend NLB target health failures (unhealthy targets terminate active connections)
- Application-layer errors causing connection closures (backend crashes, OOM kills, exception handling)
- Cross-region PrivateLink path degradation (rare but possible in multi-region deployments)
- MTU mismatch causing fragmentation failures that manifest as connection resets

**Next actions**:
- If idle timeout: Enable TCP keepalive in application (interval <300s, ideally <180s for safety margin)
- If backend health: Investigate NLB target failures (application logs, resource saturation, health check config)
- If application errors: Review application error logs, check for memory leaks, database connection pool exhaustion
- If cross-region: Use CloudWatch Network Synthetic Monitor to probe path health; consider regional service replication

**Label**: **Mixed** (idle timeout, NLB health failures **confirmed**; application-layer errors **inferred** from common patterns)

---

### Playbook 4: Backend Target Health Degradation (provider-side)

**Trigger**: **Backend Health Ratio (%)** drops below 80%, OR **Unhealthy Targets (current)** >10% of total target count, sustained >5 minutes.

**Decision rule**: If <50% healthy, escalate immediately (critical capacity impact). If 50-79%, investigate within 10 minutes.

**Steps**:
1. Check **Unhealthy Targets by Endpoint Service (top 10)** — identify which endpoint service(s) affected
2. Check **Healthy Targets (trend)** — is this a gradual degradation (slow failure) or sudden drop (crash or deployment issue)?
3. Check timing correlation with deployments or auto-scaling events — target health failures during deployments are expected (2-5 minute grace period for new targets)
4. If outside deployment windows: Check application logs on unhealthy targets — look for application crashes, OOM kills, port binding failures
5. Check NLB target group health check configuration — verify port, protocol, path, interval, timeout, healthy/unhealthy thresholds are correct
6. Check target security group — must allow inbound traffic from NLB on health check port (default: same as listener port)
7. Check **NLB Target Connection Errors (rate)** — if >1 error/s, backend targets refusing connections (backlog full, CPU saturation)
8. Check target resource utilization (EC2 CloudWatch metrics: CPU, memory, network) — if saturated, scale target count or instance size

**Likely causes**:
- Application crash or restart on targets (process died, container OOM killed)
- Health check path or port misconfigured (app listening on different port than health check expects)
- Target security group blocking NLB health check traffic
- Backend resource saturation (CPU, memory, disk) causing app unresponsiveness
- Database or dependency failure upstream (app healthy but unable to respond to health checks due to DB down)

**Next actions**:
- If application crash: Restart application on unhealthy targets; investigate crash cause (logs, core dumps)
- If health check misconfiguration: Update NLB target group health check settings (correct port, path, interval)
- If security group: Add inbound rule to target security group allowing NLB traffic on health check port
- If resource saturation: Scale target count (auto-scaling group desired capacity) or scale up instance/container size
- If dependency failure: Investigate upstream dependencies (database health, API gateway, third-party services)

**Label**: **Confirmed** (NLB health checks, target health states, connection errors documented in AWS NLB documentation)

---

### Playbook 5: Cross-Region Cost Spike

**Trigger**: **Data Processed by Region (top 5)** shows significant cross-region traffic (>20% of total data processed), AND **Data Processing Cost (USD/hour)** increasing faster than traffic growth (cross-region surcharge $0.02/GB on top of $0.01/GB base).

**Decision rule**: If cross-region cost >intra-region cost for the same traffic volume, evaluate architecture efficiency. Not urgent unless budget exceeded.

**Steps**:
1. Check **Data Processed by Region (top 5)** — identify which region pairs have high cross-region traffic (consumer region → provider region)
2. Calculate cross-region surcharge: GB cross-region * $0.02/GB * 720 hours/month
3. Check **Data Processing Cost by Endpoint (top 10)** — identify which endpoints are consuming cross-region bandwidth
4. Verify cross-region PrivateLink is intentional (regulatory requirements, DR architecture) vs accidental (misconfigured endpoint pointing to wrong region)
5. Evaluate regional service replication: Can the endpoint service be replicated to consumer regions to eliminate cross-region transfer?
6. Check application read vs write patterns — if read-heavy, regional read replicas (database, cache) can reduce cross-region traffic
7. Check if cross-region traffic can be batched or scheduled (off-peak hours for batch replication) vs real-time
8. Consider AWS Global Accelerator or CloudFront for cacheable content (alternative to PrivateLink for some use cases)

**Likely causes**:
- Centralized endpoint service in one region serving consumers in multiple regions (hub-spoke architecture)
- Application not aware of regional service availability (hard-coded to single-region endpoint)
- No regional read replicas for read-heavy workloads (all reads go cross-region to primary)
- Regulatory or data residency requirements mandate data in specific region (cross-region unavoidable)

**Next actions**:
- If accidental cross-region: Update application configuration to use intra-region endpoint services; verify endpoint region matches consumer region
- If intentional hub-spoke: Evaluate cost vs complexity trade-off for regional service replication
- If read-heavy: Deploy regional read replicas (RDS read replicas, ElastiCache replicas); update application to use regional replicas for reads
- If write-heavy: Consider active-active multi-region architecture with bidirectional replication (more complex but reduces cross-region latency)
- If cost-constrained: Batch cross-region traffic during off-peak (lower impact on real-time users); use compression to reduce GB transferred

**Label**: **Confirmed** (cross-region data transfer charges documented; pricing $0.02/GB inter-region surcharge on top of $0.01/GB base)

---

### Playbook 6: Connection Pool Exhaustion

**Trigger**: **Connection Churn Ratio** >1.0 sustained, AND **New Connections by Endpoint (top 10)** showing high rate (>10 conn/s) for database or message queue endpoints (which typically use connection pooling).

**Decision rule**: If application logs show "connection pool exhausted" or "too many connections" errors, investigate immediately (indicates connection leak or misconfiguration).

**Steps**:
1. Check **New Connections by Endpoint (top 10)** — identify which endpoints have abnormally high new connection rate
2. Check **Active Connections by Endpoint (top 10)** — compare active vs new connections (high churn = many short-lived connections)
3. Check application connection pool configuration — max pool size, max idle time, connection timeout, validation query
4. Check application logs for connection errors — "connection pool exhausted", "timeout acquiring connection", "too many connections"
5. Check backend service (database, message queue) connection limits — verify not hitting max connections (PostgreSQL max_connections, MySQL max_connections)
6. Check for connection leaks — application not closing connections (transaction timeout, exception handling missing finally block)
7. Check **Connection Churn Ratio** over time — is this new behavior (recent code change) or long-standing pattern (design issue)?
8. If connection leak: Enable application-level connection pool metrics (HikariCP, c3p0, Apache Commons DBCP); track active vs idle connections

**Likely causes**:
- Connection pool max idle time too low (connections closed prematurely, recreated frequently)
- Application connection leak (connections acquired but not closed in finally blocks)
- Backend service connection limit reached (application tries to create new connections, backend refuses)
- Short-lived Lambda or serverless functions creating new connections per invocation (connection pooling not effective)
- Application restart loops (crash, restart, create connections, crash again)

**Next actions**:
- If pool configuration: Increase max idle time (e.g., 10 minutes → 30 minutes); increase pool size if hitting limits
- If connection leak: Review application code for proper connection closing (try-finally blocks); enable connection pool leak detection
- If backend limit: Increase backend max connections (PostgreSQL: ALTER SYSTEM SET max_connections = 500); or reduce application pool size
- If serverless: Use RDS Proxy or connection pooler (PgBouncer, ProxySQL) to multiplex connections; avoid direct DB connections from Lambda
- If restart loops: Fix application crash root cause (check logs for exceptions, OOM, segfaults)

**Label**: **Inference** (connection pool patterns inferred from database client best practices; not PrivateLink-specific documentation)

---

## Playbook 7: DNS Resolution Failure for Private DNS

**Trigger**: Application logs show "unknown host", "DNS resolution failed", or "NXDOMAIN" for PrivateLink endpoint DNS names, AND **New Connections (rate)** = 0 AND **Active Connections (current)** = 0.

**Decision rule**: If private DNS is enabled for the endpoint but resolution failing, investigate immediately (full service unavailability).

**Steps**:
1. Verify private DNS is enabled for the endpoint (DescribeVpcEndpoints API or VPC console → endpoint settings)
2. Test DNS resolution manually from consumer application host: `nslookup <service-dns-name>` or `dig <service-dns-name>`
3. Check Route 53 private hosted zone existence and VPC association — private DNS creates a PHZ automatically, but VPC association can fail
4. Check VPC DNS settings (DescribeVpcAttribute API) — `enableDnsHostnames = true` and `enableDnsSupport = true` required for private DNS
5. Check Route 53 query logs (if enabled) — look for NXDOMAIN responses or no query entries (queries not reaching Route 53)
6. Check application DNS resolver configuration — verify using VPC DNS resolver (169.254.169.253), not external DNS
7. Check if split-horizon DNS is configured — private hosted zone may have incorrect records or priority issues with public DNS
8. If using custom DNS resolvers (Route 53 Resolver endpoints): Check inbound/outbound endpoint configuration and security groups

**Likely causes**:
- Private hosted zone not associated with consumer VPC (auto-association failed or manually removed)
- VPC DNS settings disabled (enableDnsHostnames or enableDnsSupport = false)
- Application using external DNS resolver (8.8.8.8, 1.1.1.1) instead of VPC DNS resolver (169.254.169.253)
- Split-horizon DNS misconfiguration (private hosted zone conflicts with public DNS records)
- Route 53 Resolver endpoint security group blocking DNS traffic (port 53 UDP/TCP)

**Next actions**:
- If PHZ not associated: Associate private hosted zone with consumer VPC (Route 53 console or API)
- If VPC DNS disabled: Enable VPC DNS settings (enableDnsHostnames and enableDnsSupport); note: requires endpoint recreation for existing endpoints
- If external DNS: Update application DNS resolver to use VPC DNS (169.254.169.253) or rely on DHCP option set
- If split-horizon issue: Validate private hosted zone records; ensure private zone has higher priority than public
- If custom resolvers: Check Route 53 Resolver endpoint security groups; verify inbound rules allow port 53 UDP/TCP from VPC CIDR

**Label**: **Confirmed** (private DNS setup, VPC DNS requirements, Route 53 private hosted zones documented)

---

## Labels Summary

- **Confirmed** chains/playbooks: 10 (based on AWS PrivateLink, NLB, VPC, Route 53 official documentation)
- **Inference** chains/playbooks: 7 (based on connection pool patterns, operational best practices, general networking principles)
- **Mixed** chains/playbooks: 3 (combination of documented AWS behavior and inferred operational patterns)

Total: 20+ triage chains, 7 operational playbooks


---

# AWS PrivateLink — Caveats & Footguns

## High-cardinality dimensions (cardinality explosion risks)

- **[endpoint-connection-health, data-transfer-performance, cost-usage]** Do NOT group by `SubnetId` in multi-AZ deployments. Each endpoint can have 2-6 ENIs (one per AZ), and subnets multiply quickly (10-100 per VPC). Use `AvailabilityZone` (max 6 per region) or `EndpointId` (top 10) instead. (Inferred from AWS VPC architecture patterns)

- **[backend-target-health]** Provider-side: Do NOT group by `PrincipalArn` in multi-tenant scenarios (1000s of consumer accounts/roles possible). Use Contributor Insights top-N rankings instead of raw group-by. (Inferred from multi-tenant SaaS patterns)

- **[endpoint-connection-health]** Do NOT group by `ConnectionState` for all endpoints simultaneously in large deployments (100s of endpoints * 5 states = 500 series). Filter to specific endpoints first, then break down by state. ([AWS re:Post guidance on CloudWatch cardinality](https://repost.aws/questions/))

- **[cost-usage]** Cross-region analysis: Grouping by `Region` is safe (typically 1-5 active regions), but combining `Region` + `EndpointId` + `ServiceName` simultaneously creates cardinality explosion. Use hierarchical filtering: filter by Region, then group by EndpointId. (Inferred from cost analysis best practices)

---

## Misleading metrics and wrong aggregations

- **[endpoint-connection-health]** `ActiveConnections` with `average` aggregation is misleading across multi-endpoint deployments. Use `sum` to see total concurrent connections; use `average` only when comparing per-endpoint behavior. ([AWS CloudWatch metrics best practices](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch_concepts.html))

- **[data-transfer-performance]** `BytesProcessed` with `max` aggregation shows the peak 1-minute sample, not total data transferred. Always use `sum` for throughput analysis and cost calculations. `max` is only useful for identifying burst windows. (Inferred from CloudWatch metric type semantics)

- **[data-transfer-performance]** Comparing `BytesProcessed` across AZs without considering `PacketDropCount` creates false equivalence. An AZ processing 10 GB with 0 drops is healthier than an AZ processing 10 GB with 1000 drops. Correlate both metrics. ([AWS PrivateLink troubleshooting guide](https://repost.aws/knowledge-center/vpc-troubleshoot-network-performance-privatelink))

- **[backend-target-health]** `HealthyHostCount` = 0 does NOT always mean outage. If the target group has no registered targets (intentional or not), healthy count is 0 but it's a configuration issue, not a health failure. Check `HealthyHostCount + UnHealthyHostCount` sum first. ([AWS NLB health check docs](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/target-group-health-checks.html))

- **[endpoint-connection-health]** `NewConnections` = 0 for sustained periods does NOT necessarily mean failure if `ActiveConnections` is stable and high. Connection-pooled applications (databases, message queues) establish connections once and reuse them. Zero new connections = healthy pool stability. ([Inference from connection pool patterns](https://en.wikipedia.org/wiki/Connection_pool))

---

## Unit pitfalls

- **[data-transfer-performance]** `BytesProcessed` is in **bytes**, not bits. Dividing by 1000000000 to get Gbps is WRONG (off by 8x). Use 125000000 bytes/s = 1 Gbps, or 1250000000 bytes/s = 10 Gbps. Tsuga normalizers handle this, but manual calculations fail. ([AWS PrivateLink bandwidth limits](https://repost.aws/knowledge-center/vpc-troubleshoot-network-performance-privatelink))

- **[cost-usage]** Data processing cost tiers are per **GB** (gigabyte), not Gb (gigabit). $0.01/GB = $0.01 per 1073741824 bytes, not per 1000000000 bytes. Use 1024-based conversion (GiB) for accuracy. ([AWS PrivateLink pricing](https://aws.amazon.com/privatelink/pricing/))

- **[backend-target-health]** NLB health check interval is in **seconds**, but CloudWatch metrics are per **minute**. A health check every 30s = 2 checks per CloudWatch data point. Comparing health check failures to metric granularity requires this conversion. ([AWS NLB health check configuration](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/target-group-health-checks.html))

- **[endpoint-connection-health]** `ActiveConnections` and `NewConnections` are measured in **1-minute windows** by CloudWatch. "Connections per second" derived signals require dividing NewConnections by 60 (or using `per-second` post-function), not treating the raw count as a rate. (Inferred from CloudWatch 1-minute granularity)

---

## Temporality pitfalls (delta vs cumulative counters)

- **[data-transfer-performance, endpoint-connection-health, cost-usage]** AWS CloudWatch metrics for PrivateLink are likely **summary type with cumulative temporality** (based on AWS ECS/SNS/Transcribe patterns from MEMORY.md). This means counters (`NewConnections`, `BytesProcessed`, `PacketDropCount`, `ResetPacketsReceived`) require `rate` post-function, NOT `per-second`. However, temporality is **UNCONFIRMED** for PrivateLink; Stage 2 discovery will validate via `/v1/metrics/metadata` endpoint. All widget specs in 07 include `# VERIFY` comments. (Inferred from AWS metric patterns; [Tsuga temporality guide](internal))

- **[data-transfer-performance]** Using `increase` post-function on `BytesProcessed` over long time windows (1+ hour) shows cumulative bytes, which can be misleading for cost calculations. Use `rate` to convert to bytes/s, then multiply by time window for accurate totals. (Inferred from Prometheus/OTel semantics)

- **[endpoint-connection-health]** `ActiveConnections` is a **gauge** (snapshot of current state), not a counter. Do NOT apply `rate` or `per-second` post-functions; use `none` or `average`/`sum` aggregations only. Applying rate to a gauge produces nonsense values. (Standard observability semantics)

- **[backend-target-health]** NLB `TargetConnectionErrorCount` is a **cumulative counter**. If you see the raw value increase from 1000 to 1050 in a 1-minute window, that's 50 new errors, not 1050 total. Always use `rate` post-function to see errors/s. ([AWS NLB metrics reference](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-metrics.html))

---

## "This looks bad but isn't" (false alarms)

- **[data-transfer-performance]** `ResetPacketsReceived` spikes during application deployments or NLB target replacements are **normal**. Graceful shutdown sends FIN, but forced termination (common in auto-scaling) sends RST. Expect 10-100 RST/s during deploy windows; only sustained elevation outside deploy windows is actionable. ([AWS deployment best practices](https://docs.aws.amazon.com/whitepapers/latest/practicing-continuous-integration-continuous-delivery/deployment-strategies.html))

- **[endpoint-connection-health]** `NewConnections` drops to zero when connection pools reach steady state (all needed connections established and reused). **This is healthy** for database or message queue clients. Only zero NewConnections + zero ActiveConnections = actual failure. ([Connection pool lifecycle patterns](https://en.wikipedia.org/wiki/Connection_pool))

- **[data-transfer-performance]** `PacketDropCount` = 1-2 drops per hour in very high throughput scenarios (approaching 10 Gbps sustained) can be **transient auto-scaling artifacts** as PrivateLink scales from 10 to 100 Gbps. Only sustained drop rates >1 drop/s or drops occurring at <5 Gbps throughput indicate real issues. ([AWS PrivateLink auto-scaling behavior, inferred](https://repost.aws/knowledge-center/vpc-troubleshoot-network-performance-privatelink))

- **[backend-target-health]** `UnHealthyHostCount` temporarily increasing to 1-2 during target launches (new EC2 instances starting, containers initializing) is **normal**. Health checks fail until application fully starts. Only sustained unhealthy counts >10% of total targets for >5 minutes is actionable. ([AWS auto-scaling health check grace periods](https://docs.aws.amazon.com/autoscaling/ec2/userguide/healthcheck.html))

- **[cost-usage]** Data processing cost doubling during backup windows or batch job runs is **expected**, not a billing error. PrivateLink charges per GB transferred; overnight ETL jobs or database replication spikes legitimately increase costs. Baseline cost during business hours, not peak windows. (Inferred from operational patterns)

- **[endpoint-connection-health]** Connection state = **Pending** for 30-60 seconds on new endpoint creation is **normal** if `acceptance_required = true` on the endpoint service. Manual approval by provider adds latency. Only Pending >1 hour without acceptance is actionable. ([AWS PrivateLink connection acceptance](https://docs.aws.amazon.com/vpc/latest/privatelink/configure-endpoint-service.html))

---

## Optional-feature traps (metrics absent unless feature enabled)

- **[endpoint-connection-health, data-transfer-performance, cost-usage]** **Cross-region PrivateLink**: `Region` dimension only exists if cross-region connectivity is enabled on the endpoint service (provider-side configuration) AND consumers in other regions have created endpoints. Absence of `Region` dimension != problem; it means single-region deployment. Dashboards must gate cross-region analysis sections accordingly. ([AWS cross-region PrivateLink launch](https://aws.amazon.com/blogs/networking-and-content-delivery/introducing-cross-region-connectivity-for-aws-privatelink/))

- **[backend-target-health]** **NLB metrics**: `HealthyHostCount`, `UnHealthyHostCount`, `TargetConnectionErrorCount` are **provider-side only**. Consumers (service users) cannot see these metrics; they're published to the service provider's CloudWatch account. Consumer-only dashboards must hide the "Backend Target Health" section entirely. Absence = expected for consumers. ([AWS PrivateLink architecture](https://docs.aws.amazon.com/vpc/latest/privatelink/concepts.html))

- **[data-transfer-performance]** **Contributor Insights**: Top-N consumer endpoint rankings (which consumers drive the most BytesProcessed, ActiveConnections, ResetPacketsReceived) require manually enabling Contributor Insights rules in the CloudWatch console. These are NOT auto-enabled. Absence = feature not enabled, not a data issue. ([AWS Contributor Insights for PrivateLink](https://aws.amazon.com/blogs/networking-and-content-delivery/gain-usage-insights-with-amazon-cloudwatch-metrics-for-aws-privatelink/))

- **[endpoint-connection-health]** **Private DNS**: DNS resolution metrics (query success/failure rates) require Route 53 query logging enabled for the private hosted zone. Private DNS itself is optional (can use endpoint-specific DNS names instead). No query logs = either private DNS not enabled OR query logging not configured. ([AWS Route 53 query logging](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/query-logs.html))

- **[data-transfer-performance]** **VPC Flow Logs**: Packet-level visibility (ENI-level traffic, REJECT actions for security group denials) requires VPC Flow Logs enabled for endpoint ENIs. Flow logs are NOT enabled by default. Absence = not configured, not a PrivateLink issue. ([AWS VPC Flow Logs](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html))

- **[backend-target-health]** **Gateway Load Balancer Endpoints (GWLBE)**: GWLBE uses same metrics as interface endpoints but serves traffic inspection use cases (firewalls, IDS/IPS). `EndpointType` dimension = "GatewayLoadBalancer" vs "Interface". Most deployments are interface-only; GWLBE metrics absent = no GWLBE deployed. ([AWS GWLB endpoints](https://docs.aws.amazon.com/vpc/latest/privatelink/vpce-gateway-load-balancer.html))

---

## Configuration and connectivity footguns

- **[endpoint-connection-health]** **Security group "connection refused"**: If `NewConnections` = 0 and application logs show "connection refused", the endpoint ENI security group is blocking traffic. PrivateLink endpoints inherit VPC security groups; default security group may deny the listener port. This is NOT a PrivateLink service issue; it's consumer-side security group misconfiguration. ([AWS troubleshooting guide](https://repost.aws/questions/QUjamZ-8IgSc-KTI5Q4Kg0vg/privatelink-connectivity-issues))

- **[endpoint-connection-health]** **DNS resolution failures**: If private DNS is enabled but DNS queries fail (NXDOMAIN), the private hosted zone may not be associated with the consumer VPC, or VPC DNS settings (enableDnsHostnames, enableDnsSupport) may be disabled. PrivateLink creates the hosted zone, but VPC association is NOT automatic in all scenarios. ([AWS PrivateLink DNS setup](https://docs.aws.amazon.com/vpc/latest/privatelink/privatelink-access-aws-services.html))

- **[data-transfer-performance]** **Idle timeout resets (350s)**: `ResetPacketsReceived` spiking every ~6 minutes (350s idle timeout) means clients are not sending TCP keepalive packets. Long-lived connections (WebSockets, streaming) require application-layer keepalive or TCP keepalive enabled. This is NOT a PrivateLink bug; it's standard AWS networking behavior. ([AWS idle timeout docs](https://repost.aws/knowledge-center/vpc-troubleshoot-network-performance-privatelink))

- **[data-transfer-performance]** **MTU mismatches**: `PacketDropCount` correlated with large transfers (>1500 byte packets) indicates MTU mismatch between consumer VPC (typically 9001 MTU for jumbo frames within VPC) and endpoint ENI. PrivateLink does NOT support jumbo frames; MTU is capped at 1500. Enable Path MTU Discovery (PMTUD) in applications. ([AWS VPC MTU documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/network_mtu.html))

- **[endpoint-connection-health]** **Connection state = Rejected**: Service provider explicitly rejected the connection request, OR the consumer's AWS account/IAM principal is not in the endpoint service's allowed principals list. This is an authorization failure, not a connectivity failure. Consumers must request access from the provider. ([AWS PrivateLink connection states](https://docs.aws.amazon.com/vpc/latest/privatelink/configure-endpoint-service.html))

- **[backend-target-health]** **NLB target health check failures**: If consumer-side `ResetPacketsReceived` correlates with provider-side `UnHealthyHostCount` increases, the NLB health check is failing (target not responding on health check port/path). This is a backend service issue (app crashed, port blocked), not a PrivateLink issue. ([AWS NLB health check troubleshooting](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/target-group-health-checks.html))

- **[cost-usage]** **Cross-AZ data transfer costs**: If `BytesProcessed` is high but data processing cost is higher than expected, check if consumer endpoint AZs align with provider NLB AZs. Mismatched AZs incur cross-AZ data transfer charges ($0.01/GB inbound + $0.01/GB outbound) ON TOP OF PrivateLink data processing charges. Multi-AZ for HA is correct, but understand cost implications. ([AWS data transfer pricing](https://aws.amazon.com/ec2/pricing/on-demand/))

---

## Confirmed by sources
- 350-second idle timeout ([AWS re:Post](https://repost.aws/knowledge-center/vpc-troubleshoot-network-performance-privatelink))
- 10 Gbps baseline, auto-scales to 100 Gbps per AZ ([same source](https://repost.aws/knowledge-center/vpc-troubleshoot-network-performance-privatelink))
- Connection states (Pending, Available, Rejected, Failed, Expired) ([AWS docs](https://docs.aws.amazon.com/vpc/latest/privatelink/configure-endpoint-service.html))
- NLB metrics (HealthyHostCount, UnHealthyHostCount, TargetConnectionErrorCount) ([AWS NLB docs](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-metrics.html))
- Contributor Insights for PrivateLink ([AWS blog](https://aws.amazon.com/blogs/networking-and-content-delivery/gain-usage-insights-with-amazon-cloudwatch-metrics-for-aws-privatelink/))
- Private DNS setup ([AWS docs](https://docs.aws.amazon.com/vpc/latest/privatelink/privatelink-access-aws-services.html))
- MTU limits (1500 bytes for PrivateLink) ([AWS VPC MTU docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/network_mtu.html))
- Cross-region PrivateLink launch ([AWS blog](https://aws.amazon.com/blogs/networking-and-content-delivery/introducing-cross-region-connectivity-for-aws-privatelink/))

## Best-practice inference
- Temporality (delta vs cumulative) inferred from AWS ECS/SNS/Transcribe patterns documented in MEMORY.md
- High-cardinality risks (SubnetId, PrincipalArn) inferred from general AWS multi-tenant and multi-VPC architecture patterns
- Connection pool behavior (NewConnections = 0 is healthy) inferred from standard database and message queue client patterns
- Cross-AZ cost implications inferred from AWS data transfer pricing model (not PrivateLink-specific)
- Auto-scaling transient packet drops inferred from general AWS elastic scaling behavior
- Health check grace periods during target launches inferred from EC2 auto-scaling best practices


---

