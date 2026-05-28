# AWS ECS Integration Context Bundle

**Technology:** AWS ECS (Elastic Container Service)
**Deployment:** Managed (AWS)
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** mixed
**Integration scope:** core service only
**Primary use-case:** reliability and performance

---

## How to use this bundle

- **Dashboard plan:** `07_aws-ecs_dashboard_plan.yaml` — section structure, widget specs, gating rules, coverage map
- **Metric truth:** `05_aws-ecs_metric_inventory.csv` — source of truth for all metrics, units, temporality, Tsuga mapping, aggregations
- **Notes & playbooks:** `09_aws-ecs_section_notes_and_playbooks.md` — all note prose, triage chains, operational playbooks
- **Reconciliation:** `12_aws-ecs_discovery_reconciliation.md` — Stage 2 discovery results, confirmed/missing/unexpected metrics

---

## Confirmed Tsuga prefixes

- `aws_ecs_*` — **CONFIRMED** (11 metrics found; maps CloudWatch AWS/ECS namespace: cpu_utilization, memory_utilization, request_count, target_response_time, Service Connect metrics)
- `ecs_containerinsights_*` — **CONFIRMED** (25 metrics found; maps CloudWatch ECS/ContainerInsights namespace: running_task_count, cpu_utilized, memory_utilized, network_rx_bytes, plus 6 Enhanced Observability metrics)

> **Naming convention:** Tsuga uses underscore-separated snake_case for all ECS metrics. No dots or PascalCase.
> **Context fields:** All lowercase joined — `context.servicename`, `context.clustername`, `context.taskdefinitionfamily`, `context.discoveryname`, `context.targetdiscoveryname`.
> **Counter temporality:** All metrics are `summary` type with `cumulative` temporality. Counters use `sum` + `rate`; gauges use `avg` + `none`.

---

## Discovery status

Discovery: **COMPLETE** (Stage 2 performed 2026-02-10)

- **36 metrics confirmed** in Tsuga (11 aws_ecs + 25 ecs_containerinsights)
- **11 metrics not found** — EC2-only (CPUReservation, MemoryReservation, GPUReservation), EBS (EBSFilesystemUtilization, EBSFilesystemSize, EBSFilesystemUtilized), HTTP error codes (3XX, 4XX, 5XX), TLS errors (Client, Target). All gated in dashboard plan.
- **6 unexpected Enhanced Observability metrics** added — ContainerCpuUtilization, ContainerMemoryUtilization, UnHealthyContainerHealthStatus, TaskCpuUtilization, TaskMemoryUtilization, TaskEphemeralStorageUtilization
- **Account profile:** Fargate-only (no EC2 reservation metrics), Service Connect enabled, Enhanced Observability enabled

---

## Bundle files

| # | Filename | Purpose |
|---|----------|---------|
| 00 | `00_aws-ecs_cover.md` | This file — metadata, prefixes, sources, navigation |
| 01 | `01_aws-ecs_executive_overview.md` | What "good" looks like, incident shapes, dashboard intent |
| 02 | `02_aws-ecs_key_concepts.md` | Glossary (24 terms), concept map (28 lines), entities (16), context.* mapping |
| 03 | `03_aws-ecs_golden_signals.md` | Traffic/Errors/Latency/Saturation mapping to section questions |
| 04 | `04_aws-ecs_telemetry_sources.md` | Source matrix, optional features, "no data" meanings |
| 05 | `05_aws-ecs_metric_inventory.csv` | 47 metrics: names, units, types, Tsuga mapping, aggregations, group-bys |
| 06 | `06_aws-ecs_derived_signals.csv` | 14 derived signals: formulas, inputs, gating, interpretation |
| 07 | `07_aws-ecs_dashboard_plan.yaml` | 6 sections, ~60 widgets, coverage map, gating rules |
| 09 | `09_aws-ecs_section_notes_and_playbooks.md` | Mission note, 6 section notes, 22 triage chains, 8 playbooks |
| 10 | `10_aws-ecs_caveats_footguns.md` | 23 caveats tagged to sections |
| 11 | `11_aws-ecs_unknowns_verify_next.yaml` | Remaining unknowns after Stage 2 discovery |
| 12 | `12_aws-ecs_discovery_reconciliation.md` | Stage 2 discovery results, reconciliation details |

---

## Top sources

1. **[AWS ECS CloudWatch Metrics](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/available-metrics.html)** — Definitive reference for AWS/ECS namespace metrics (CPUUtilization, MemoryUtilization, Service Connect metrics), dimensions, and statistics.
2. **[AWS Container Insights Metrics for ECS](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-ECS.html)** — Complete list of ECS/ContainerInsights namespace metrics, dimensions, and enablement requirements.
3. **[Container Insights Enhanced Observability](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-enhanced-observability-metrics-ECS.html)** — Container-level and task-level metrics available with enhanced observability tier.
4. **[AWS ECS Developer Guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/Welcome.html)** — Architecture, concepts, task definitions, services, deployments, capacity providers.
5. **[How Amazon ECS Manages CPU and Memory](https://aws.amazon.com/blogs/containers/how-amazon-ecs-manages-cpu-and-memory-resources/)** — Deep dive on CPU soft/hard limits, burst behavior, and memory semantics across EC2 and Fargate.
6. **[AWS ECS Stopped Task Error Codes](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/stopped-task-error-codes.html)** — Complete list of stop codes (OOM, TaskFailedToStart, etc.) and their meanings.
7. **[Setting up Container Insights on ECS](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/deploy-container-insights-ECS-cluster.html)** — How to enable Container Insights standard and enhanced tiers.
8. **[AWS Fargate for ECS](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)** — Fargate-specific constraints: CPU/memory combinations, networking, ephemeral storage, platform versions.
9. **[ECS Task State Change Events](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_task_events.html)** — EventBridge integration for task lifecycle, stop codes, and failure diagnostics.
10. **[AWS ECS Prescriptive Guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/implementing-logging-monitoring-cloudwatch/ecs-metrics.html)** — AWS best practices for ECS monitoring and metrics selection.


---

# AWS ECS — Executive Overview

## What it is
AWS Elastic Container Service (ECS) is a fully managed container orchestration service that runs Docker containers on AWS infrastructure. Workloads run on either **Fargate** (serverless, AWS-managed compute) or **EC2** (self-managed instances). ECS manages the lifecycle of services (long-running tasks with desired count), standalone tasks, and scheduled tasks across clusters.

## What "good" looks like
- **RunningTaskCount == DesiredTaskCount** for every service (no pending or failed tasks).
- **CPU and memory utilization** between 30-70% at service level — enough headroom for spikes, not wasting capacity.
- **PendingTaskCount near zero** — tasks launch quickly and transition to RUNNING.
- **DeploymentCount == 1** per service — no stuck or rolling-back deployments.
- **RestartCount stable** — not climbing, indicating container stability.
- Zero sustained 5xx errors from Service Connect (if enabled).

## Paging intent
- Service unable to maintain desired task count (tasks failing to start or being killed).
- CPU or memory utilization sustained above 85% with no auto-scaling headroom.
- Deployment stuck: DeploymentCount > 1 for extended period with RunningTaskCount < DesiredTaskCount.

## Top 3 incident shapes

| Incident | First dashboard section |
|----------|----------------------|
| **Tasks failing to start / OOM kills** — RunningTaskCount drops below DesiredTaskCount, PendingTaskCount spikes, RestartCount climbs. Common causes: OOM, image pull failures, resource exhaustion. | Task Lifecycle & Deployments |
| **CPU/memory saturation** — CPUUtilization or MemoryUtilization sustained near 100%. Containers throttled, latency increases, potential OOM kills. | Resource Utilization |
| **Deployment rollback / stuck deployment** — DeploymentCount > 1, new tasks not reaching RUNNING state. Circuit breaker may trigger automatic rollback. | Task Lifecycle & Deployments |

---

### Confirmed by sources
- Task lifecycle states, stop codes, and deployment circuit breaker behavior: [AWS ECS Developer Guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-event-messages.html)
- CPU/memory utilization metric definitions and Fargate vs EC2 differences: [AWS ECS CloudWatch Metrics](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/available-metrics.html)
- Container Insights task count and health metrics: [AWS Container Insights Metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-ECS.html)

### Best-practice inference
- The 30-70% utilization target range is industry-standard SRE guidance, not AWS-specific documentation.
- "DeploymentCount == 1 means healthy" is inferred from how ECS manages rolling deployments (old deployment persists until new one stabilizes).


---

# AWS ECS — Key Concepts

## Glossary (24 terms)

| Term | Definition | Operational Meaning | Dashboard Section |
|------|-----------|---------------------|-------------------|
| **Cluster** | Logical grouping of tasks and services. Provides isolation and capacity infrastructure. | Top-level scope for all dashboards. Global filter target. | All sections |
| **Service** | Maintains a desired count of task instances with deployment management and LB integration. | Primary operational unit. RunningTaskCount vs DesiredTaskCount is the health signal. | Task Lifecycle & Deployments |
| **Task** | A running instantiation of a task definition. Contains one or more containers. | The unit of work. Lifecycle state (PENDING → RUNNING → STOPPED) drives health metrics. | Task Lifecycle & Deployments |
| **Task Definition** | Blueprint (JSON) specifying container images, CPU/memory limits, networking, IAM roles. Versioned as family:revision. | Family name is the primary group-by dimension for per-workload breakdowns. | Resource Utilization |
| **Container** | Individual Docker container within a task. Essential containers stop the whole task on exit. | Container-level metrics require Enhanced Container Insights. | Resource Utilization |
| **Fargate** | Serverless launch type. AWS manages compute. Fixed CPU/memory combinations. No burst. | No cluster-level reservation metrics. Ephemeral storage metrics available. | Resource Utilization, Storage |
| **EC2 Launch Type** | Self-managed EC2 instances registered with the cluster. Allows GPU, flexible CPU/memory. | Adds CPUReservation/MemoryReservation and instance-level metrics. | Resource Utilization, Capacity |
| **Capacity Provider** | Abstraction for compute supply: FARGATE, FARGATE_SPOT, or Auto Scaling Group. | Determines available compute and cost model. Capacity provider name is a useful group-by. | Capacity & Scaling |
| **Desired Count** | Target number of running tasks for a service. Set manually or by auto-scaling. | DesiredTaskCount is the baseline. RunningTaskCount < DesiredTaskCount means trouble. | Task Lifecycle & Deployments |
| **Deployment** | A change to a service (new revision, count change). Rolling update with min/max healthy percent. | DeploymentCount > 1 = active deployment in progress. Sustained > 1 = stuck. | Task Lifecycle & Deployments |
| **Circuit Breaker** | Auto-rollback mechanism when tasks repeatedly fail to reach RUNNING state. | Prevents bad deployments from fully rolling out. Creates rollback deployment events. | Task Lifecycle & Deployments |
| **Service Connect** | Service mesh proxy (Envoy-based) for ECS service-to-service communication. | Provides traffic metrics (RequestCount, latency, HTTP status codes). Feature-gated. | Service Connect Traffic |
| **Container Insights** | CloudWatch feature providing cluster/service/task-level telemetry for ECS. Must be explicitly enabled. | Required for most Container Insights metrics. Standard vs Enhanced tiers. | All Container Insights sections |
| **Enhanced Observability** | Container Insights tier adding container-level and task-level (TaskId) breakdown metrics. | Adds ContainerCpuUtilization, ContainerMemoryUtilization, UnHealthyContainerHealthStatus. | Resource Utilization (container-level) |
| **CPUUtilization** | Percentage of CPU units in use. Service-level (Fargate+EC2) or cluster-level (EC2 only). | Primary saturation signal. 100% = throttling on Fargate. | Resource Utilization |
| **MemoryUtilization** | Percentage of memory in use. Service-level (Fargate+EC2) or cluster-level (EC2 only). | Approaching 100% = OOM kill risk. | Resource Utilization |
| **CPUReservation** | Percentage of registered CPU units reserved by running tasks (EC2 only). | High reservation = cluster needs more instances. | Capacity & Scaling |
| **MemoryReservation** | Percentage of registered memory reserved by running tasks (EC2 only). | Often the binding constraint for task placement on EC2. | Capacity & Scaling |
| **RunningTaskCount** | Tasks in RUNNING state for a service. | Must equal DesiredTaskCount. Gap = problem. | Task Lifecycle & Deployments |
| **PendingTaskCount** | Tasks in PENDING state for a service (waiting for resources or scheduling). | Should be near zero. Sustained pending = placement failure or resource shortage. | Task Lifecycle & Deployments |
| **RestartCount** | Cumulative container restart count. Monotonically increasing counter. | Rising slope = containers crashing and restarting. | Task Lifecycle & Deployments |
| **OOM Kill** | Out Of Memory kill. Container exceeds memory hard limit. Stop code: OutOfMemoryError. | Memory utilization near 100% preceding a task stop. | Resource Utilization |
| **Stop Code** | Reason a task was stopped (OutOfMemoryError, TaskFailedToStart, SpotInterruptionError, etc.). | Key diagnostic dimension for failed task analysis. Available via EventBridge, not as a metric dimension. | Task Lifecycle & Deployments |
| **awsvpc Network Mode** | Each task gets its own ENI and private IP. Required for Fargate. Optional for EC2. | Enables network metrics (NetworkRxBytes, NetworkTxBytes). Other modes have limited visibility. | Network I/O |

---

## Concept Map (28 lines)

```
Cluster -> contains -> Service (why: services are the operational unit within a cluster)
Cluster -> contains -> Standalone Task (why: batch jobs or one-off tasks run without a service)
Cluster -> has -> Capacity Provider (why: determines compute supply — Fargate, EC2, Spot)
Service -> maintains -> Desired Task Count (why: defines the expected steady state)
Service -> creates -> Deployment (why: every change triggers a new deployment)
Service -> registers with -> Load Balancer (why: distributes traffic to task targets)
Deployment -> launches -> Task (why: tasks are the runtime instantiation of a deployment)
Deployment -> monitored by -> Circuit Breaker (why: auto-rollback on repeated failures)
Task -> defined by -> Task Definition (why: blueprint for containers, resources, IAM)
Task -> contains -> Container (why: one or more containers share resources and network)
Task -> has -> Launch Type: Fargate or EC2 (why: determines compute model and metric availability)
Task -> has -> Lifecycle State (why: PENDING → RUNNING → STOPPED drives health signals)
Task -> has -> Stop Code (why: explains why a task stopped — OOM, Spot interruption, etc.)
Container -> has -> CPU Limit (why: hard limit = throttling on Fargate, soft limit = burstable on EC2)
Container -> has -> Memory Limit (why: exceeding hard limit = OOM kill)
Container -> may have -> Health Check (why: UnHealthyContainerHealthStatus metric)
CPUUtilization -> approximates -> CPU Saturation (why: 100% = throttled on Fargate, may burst on EC2)
MemoryUtilization -> predicts -> OOM Risk (why: approaching 100% precedes OOM kills)
CPUReservation -> measures -> Cluster Capacity Used (why: EC2 only; high = need more instances)
MemoryReservation -> measures -> Cluster Capacity Used (why: often binding constraint for EC2 placement)
RunningTaskCount -> compared to -> DesiredTaskCount (why: gap = unhealthy service)
PendingTaskCount -> indicates -> Placement Failures (why: sustained pending = resource shortage)
RestartCount -> indicates -> Container Instability (why: monotonically increasing = crash loops)
NetworkRxBytes -> measures -> Inbound Traffic (why: requires awsvpc or bridge network mode)
NetworkTxBytes -> measures -> Outbound Traffic (why: requires awsvpc or bridge network mode)
Service Connect -> provides -> Request Metrics (why: L7 traffic visibility — counts, latency, HTTP codes)
Container Insights -> enables -> Task/Service Metrics (why: must be explicitly enabled on the cluster)
Enhanced Observability -> enables -> Container-level Metrics (why: adds per-container and per-TaskId breakdown)
```

---

## Entities and Dimensions (16)

| Dimension | Vendor Name | Tsuga `context.*` Mapping | Cardinality | Safe Top-N | Notes |
|-----------|-------------|--------------------------|-------------|-----------|-------|
| Cluster Name | `ClusterName` | `context.cluster_name` | Low (1-20) | 10 | **Must-exist.** Top-level scope for all dashboards. |
| Service Name | `ServiceName` | `context.service_name` | Low-Medium (5-100) | 25 | **Must-exist.** Primary operational unit. |
| Task Definition Family | `TaskDefinitionFamily` | `context.task_definition_family` | Low-Medium (5-100) | 25 | Must-exist. Group workloads without service coupling. |
| Container Name | `ContainerName` | `context.container_name` | Low (1-10 per task) | 10 | Optional. Enhanced Observability only. |
| Task ID | `TaskId` | `context.task_id` | **HIGH** (hundreds-thousands) | 10 | **Do NOT group-by** in dashboards. Use only for drill-down filters. Enhanced Observability only. |
| Instance ID | `InstanceId` / `EC2InstanceId` | `context.instance_id` | Medium (10-500) | 25 | EC2 only. Instance-level metrics. |
| Container Instance ID | `ContainerInstanceId` | `context.container_instance_id` | Medium (10-500) | 25 | EC2 only. ECS agent on the instance. |
| Capacity Provider | `CapacityProviderName` | `context.capacity_provider_name` | Very Low (1-5) | 5 | Useful for Fargate vs Spot vs EC2 breakdown. |
| Discovery Name | `DiscoveryName` | `context.discovery_name` | Low (5-50) | 15 | Service Connect only. Service mesh endpoint name. |
| Target Discovery Name | `TargetDiscoveryName` | `context.target_discovery_name` | Low (5-50) | 15 | Service Connect only. Target endpoint name. |
| Volume Name | `VolumeName` | `context.volume_name` | Low (1-10 per task) | 10 | EBS volume metrics only. |
| Region | (AWS tag) | `context.cloud.region` | Very Low (1-10) | 10 | Standard cloud dimension. |
| Account ID | (AWS tag) | `context.cloud.account.id` | Very Low (1-10) | 10 | Multi-account deployments. |
| Environment | (custom tag) | `context.env` | Very Low (2-5) | 5 | **Must-exist.** Global filter. |
| Team | (custom tag) | `context.team` | Low (5-20) | 10 | **Must-exist.** Global filter. |
| Launch Type | `LaunchType` | `context.launch_type` | Very Low (2-3) | 3 | Unknown if available as a tag in Tsuga. Useful for Fargate vs EC2 breakdowns. |

### Do NOT group-by
- **`context.task_id`** — Very high cardinality (hundreds to thousands of unique values). Creates unreadable charts and high query cost. Use only as a filter for targeted investigation.
- **`context.container_instance_id`** — Prefer `context.instance_id` for EC2 instance breakdown; container instance ID is an ECS-internal reference less useful for operators.

---

## Tsuga Field Mapping Table

| Vendor/CloudWatch Dimension | Recommended `context.*` Key | Status | Must-exist? |
|-----------------------------|----------------------------|--------|-------------|
| `ClusterName` | `context.cluster_name` | **Unknown** — verify in Stage 2 | Yes |
| `ServiceName` | `context.service_name` | **Unknown** — verify in Stage 2 | Yes |
| `TaskDefinitionFamily` | `context.task_definition_family` | **Unknown** — verify in Stage 2 | Yes |
| `ContainerName` | `context.container_name` | **Unknown** — verify in Stage 2 (Enhanced only) | No |
| `TaskId` | `context.task_id` | **Unknown** — verify in Stage 2 (Enhanced only) | No |
| `InstanceId` / `EC2InstanceId` | `context.instance_id` | **Unknown** — verify in Stage 2 (EC2 only) | No |
| `ContainerInstanceId` | `context.container_instance_id` | **Unknown** — verify in Stage 2 (EC2 only) | No |
| `CapacityProviderName` | `context.capacity_provider_name` | **Unknown** — verify in Stage 2 | No |
| `DiscoveryName` | `context.discovery_name` | **Unknown** — verify in Stage 2 (Service Connect only) | No |
| `TargetDiscoveryName` | `context.target_discovery_name` | **Unknown** — verify in Stage 2 (Service Connect only) | No |
| `VolumeName` | `context.volume_name` | **Unknown** — verify in Stage 2 | No |
| (AWS tag) | `context.cloud.region` | **Inferred** — standard AWS tag | No |
| (AWS tag) | `context.cloud.account.id` | **Inferred** — standard AWS tag | No |
| (custom) | `context.env` | **Inferred** — from .env config | Yes |
| (custom) | `context.team` | **Inferred** — from .env config | Yes |
| `LaunchType` | `context.launch_type` | **Unknown** — may or may not be a tag | No |

> All `context.*` field names are Unknown until Stage 2 discovery confirms them. The names above follow Tsuga naming conventions observed in other AWS integrations.

---

### Confirmed by sources
- ECS architecture (clusters, services, tasks, task definitions, capacity providers): [AWS ECS Developer Guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/Welcome.html)
- CloudWatch metric dimensions: [AWS ECS Available Metrics](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/available-metrics.html)
- Container Insights dimensions and enhanced observability: [AWS Container Insights Metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-ECS.html)
- Fargate vs EC2 capability differences: [AWS Fargate Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)

### Best-practice inference
- `context.*` field name mappings are inferred from Tsuga naming conventions. Actual field names may differ (e.g., `context.ecs.cluster_name` vs `context.cluster_name`). Stage 2 discovery will resolve.
- Top-N suggestions (25 for services, 10 for clusters) are based on typical deployment sizes.
- The "Do NOT group-by" guidance for task_id is based on cardinality risk analysis, not Tsuga-specific documentation.


---

# AWS ECS — Golden Signals

## Traffic

**What it means for ECS:**
Traffic measures the volume of work flowing through ECS — task execution, network I/O, and (with Service Connect) HTTP/gRPC request throughput. Unlike request-serving systems, ECS itself is an orchestration layer, so "traffic" is primarily measured at the network and service-mesh level, plus the number of tasks being scheduled and executed.

**Typical causes when it degrades:**
- Upstream callers reducing load (planned or unplanned)
- Auto-scaling reducing desired count during low-traffic periods
- Network connectivity issues between tasks and load balancers
- Service Connect proxy failures silently dropping traffic

**Best telemetry sources:**
- `NetworkRxBytes` / `NetworkTxBytes` (Container Insights) — network throughput per task/service
- `RequestCount` / `ProcessedBytes` (Service Connect) — L7 request volume
- `RunningTaskCount` — proxy for compute capacity handling traffic

**What people page on:**
- Network throughput drops to zero or near-zero on a service that normally has steady traffic
- Service Connect RequestCount drops significantly without a corresponding desired count change
- RunningTaskCount drops below DesiredTaskCount (capacity to serve traffic is reduced)

**Section questions:**
1. Is the cluster handling expected network traffic? (Network I/O)
2. What is the request volume through Service Connect? (Service Connect Traffic)

---

## Errors

**What it means for ECS:**
Errors in ECS manifest as tasks failing to start, containers being OOM-killed, health check failures, and (with Service Connect) HTTP 4xx/5xx responses. Task-level errors are the most critical — they indicate workloads are not running as expected.

**Typical causes when it degrades:**
- **OOM kills**: Container exceeds memory hard limit (OutOfMemoryError stop code)
- **Image pull failures**: Bad image tag, ECR authentication expired, registry unreachable (CannotPullContainer)
- **Resource exhaustion**: No capacity for task placement on EC2 clusters
- **Application errors**: 5xx responses through Service Connect indicate application failures
- **TLS errors**: Service Connect TLS negotiation failures (misconfigured certificates)

**Best telemetry sources:**
- `RestartCount` (Container Insights) — container crash loops
- `UnHealthyContainerHealthStatus` (Enhanced Observability) — health check failures
- `HTTPCode_Target_5XX_Count` / `4XX_Count` (Service Connect) — application errors
- `RunningTaskCount` vs `DesiredTaskCount` gap — task failures
- `ClientTLSNegotiationErrorCount` / `TargetTLSNegotiationErrorCount` (Service Connect) — TLS errors

**What people page on:**
- RestartCount climbing rapidly across multiple containers (crash loop)
- Sustained gap between RunningTaskCount and DesiredTaskCount (tasks failing to start)
- 5xx error rate exceeding a threshold through Service Connect
- UnHealthyContainerHealthStatus showing unhealthy containers

**Section questions:**
1. Are tasks running successfully or failing? (Task Lifecycle & Deployments)
2. Are Service Connect endpoints returning errors? (Service Connect Traffic)

---

## Latency

**What it means for ECS:**
Latency in ECS is primarily visible through Service Connect's `TargetResponseTime` metric, which measures proxy-to-target response time. Without Service Connect, ECS itself doesn't expose latency metrics — applications must instrument their own. Task startup time (PENDING → RUNNING duration) is an infrastructure latency signal.

**Typical causes when it degrades:**
- CPU throttling causing application slowdown (CPUUtilization at 100% on Fargate)
- Memory pressure causing garbage collection pauses
- Network congestion between services
- Slow image pulls during task startup (cold start latency)
- ENI provisioning delays for Fargate tasks in awsvpc mode

**Best telemetry sources:**
- `TargetResponseTime` (Service Connect) — proxy-to-target latency
- `CPUUtilization` — indirect: high CPU correlates with increased latency
- `PendingTaskCount` duration — how long tasks stay in PENDING (no direct metric; inferred from count trends)

**What people page on:**
- TargetResponseTime p95/p99 spiking above SLO thresholds
- CPUUtilization sustained at 100% with latency complaints from consumers
- PendingTaskCount elevated for extended period (task startup delay)

**Section questions:**
1. How fast are Service Connect endpoints responding? (Service Connect Traffic)

---

## Saturation

**What it means for ECS:**
Saturation measures how close ECS resources are to their limits. This includes CPU and memory utilization at the task/service level, cluster-level reservation (EC2 only), storage consumption, and the gap between running and desired task counts (which indicates scheduling pressure).

**Typical causes when it degrades:**
- Workload growth exceeding allocated CPU/memory per task
- Auto-scaling not keeping up with demand
- EC2 cluster running out of registered instance capacity (high reservation)
- Ephemeral storage filling up (Fargate)
- EBS volume reaching filesystem capacity limits
- Too many tasks competing for limited EC2 instance resources

**Best telemetry sources:**
- `CPUUtilization` / `MemoryUtilization` (AWS/ECS) — service and cluster level
- `CpuUtilized` vs `CpuReserved`, `MemoryUtilized` vs `MemoryReserved` (Container Insights) — absolute values
- `CPUReservation` / `MemoryReservation` (AWS/ECS, EC2 only) — cluster capacity
- `EphemeralStorageUtilized` vs `EphemeralStorageReserved` (Container Insights, Fargate only)
- `EBSFilesystemUtilization` (AWS/ECS) — EBS storage pressure
- `StorageReadBytes` / `StorageWriteBytes` (Container Insights) — I/O volume

**What people page on:**
- CPUUtilization or MemoryUtilization sustained above 85% with no auto-scaling response
- CPUReservation or MemoryReservation above 80% on EC2 clusters (can't place new tasks)
- EBSFilesystemUtilization approaching 90%+ (disk full risk)
- MemoryUtilization approaching 100% (OOM kill imminent)

**Section questions:**
1. How utilized are CPU and memory across services? (Resource Utilization)
2. Is the cluster running out of capacity? (Capacity & Scaling — EC2 only)
3. How is storage being consumed? (Storage & I/O)

---

### Confirmed by sources
- CloudWatch metric definitions and dimensions: [AWS ECS CloudWatch Metrics](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/available-metrics.html)
- Container Insights metric definitions: [AWS Container Insights Metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-ECS.html)
- Service Connect metrics: [AWS ECS Service Connect Metrics](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/available-metrics.html)
- Stopped task error codes and lifecycle: [AWS ECS Stopped Tasks](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/stopped-task-error-codes.html)
- Fargate CPU/memory limits: [AWS Fargate Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)

### Best-practice inference
- Task startup latency (PENDING → RUNNING) is a known operational concern but has no direct CloudWatch metric — inferred from PendingTaskCount trends.
- The 85% utilization paging threshold is industry SRE convention, not AWS-specific.
- Latency correlation with CPUUtilization is standard observability practice, not documented by AWS for ECS specifically.


---

# AWS ECS — Section Notes & Playbooks

---

## Part 1: Overview Mission Note

**AWS Elastic Container Service (ECS)** — managed container orchestration running workloads on Fargate (serverless) or EC2 instances.

**Scope:** Covers all ECS clusters, services, and tasks reporting via CloudWatch and Container Insights. Service Connect traffic metrics require Service Connect to be configured. EC2 cluster capacity metrics require EC2 launch type.

**Links:**
- [AWS ECS Developer Guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/Welcome.html)
- [Container Insights Metrics Reference](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-ECS.html)
- [Deep Dive Dashboard →](#)

---

## Part 2: Section Explanation Notes

### # Tasks & Deployments - Are services running the expected number of tasks?

#### So what?
Healthy services maintain **RunningTaskCount == DesiredTaskCount** with **PendingTaskCount near zero**. The key signal is the **Task Deficit** — any sustained gap means tasks are failing to start or being killed. **DeploymentCount > 1** during a rolling update is normal, but if it persists beyond the expected rollout window, the deployment is stuck or rolling back (circuit breaker). **Restart Rate > 0** means containers are crashing — correlate with memory utilization for OOM kills. Watch out: PendingTaskCount > 0 for a few seconds during scale-out is expected, not an incident.

#### Now what?
Check **Task Deficit** → if positive, check **Pending Tasks by Service** for which services are affected → check **Restart Rate by Service** for crash loops → if restarts are climbing with high memory, likely OOM — increase task memory limits or investigate memory leaks.

---

### # Resource Utilization - How utilized are CPU and memory across services?

#### So what?
**CPU and Memory Utilization** between 30-70% indicates healthy headroom. **CPUUtilization** at 100% on Fargate means hard throttling (no burst). On EC2 it can exceed 100% if no hard CPU limit is set — this is normal burst behavior, not an error. **Memory approaching 100%** is always concerning: on Fargate it means OOM kill is imminent. Watch out: `CpuUtilized`/`CpuReserved` are in **CPU units** (not percent); `MemoryUtilized`/`MemoryReserved` are in **MiB**. Don't confuse with the percentage-based utilization metrics.

#### Now what?
Check **Top Services by CPU/Memory** → identify which services are hottest → compare **Utilized vs Reserved** to assess over/under-provisioning → if utilization is high and tasks are restarting, likely need to increase task resource limits or scale out the service.

---

### # Network - Is the cluster handling expected network traffic?

#### So what?
**NetworkRxBytes** and **NetworkTxBytes** show per-service throughput. A drop to zero on a normally active service signals connectivity failure. A sudden spike may indicate traffic flood or batch processing. These metrics are already rates (Bytes/Second) — do NOT apply per-second post-function. Watch out: Network metrics only work with **awsvpc** and **bridge** network modes. `host` mode reports zero — that's expected, not broken.

#### Now what?
Check **Network In/Out by Service** → identify which services have unusual patterns → if traffic drops, correlate with **RunningTaskCount** (are tasks down?) and **Service Connect Request Rate** (are requests failing?) → if spikes, check if auto-scaling is responding.

---

### # Storage - How is storage being consumed and how fast is I/O?

#### So what?
**Storage I/O Rate** shows combined read+write throughput. High write rates may indicate heavy logging or temp file activity. **Ephemeral Storage Utilization** (Fargate only) above 80% risks hitting the storage limit — Fargate tasks that exceed ephemeral storage are stopped. **EBS Filesystem Utilization** above 90% means disk-full is imminent. Watch out: Ephemeral storage metrics are Fargate-only (platform v1.4.0+). EBS metrics only exist if EBS volumes are attached.

#### Now what?
Check **Storage Read vs Write** for I/O pattern → if writes dominate, check logging configuration or temp file cleanup → check **Ephemeral Storage %** for Fargate services → if approaching limit, increase ephemeral storage in task definition or reduce disk usage.

---

### # Capacity - Is the EC2 cluster running out of room?

#### So what?
**CPU/Memory Reservation** shows what percentage of registered EC2 cluster capacity is reserved by running tasks. **Headroom** below 20% means new tasks may fail to place. Memory is often the binding constraint — it runs out before CPU. Watch out: Reservation is **EC2 only**. If you use Fargate exclusively, these metrics will be 0% or absent — that's expected. Also, newly launching instances aren't counted until they register as ACTIVE, causing a brief lag in headroom calculations.

#### Now what?
Check **CPU & Memory Reservation Over Time** → if trending up, verify capacity provider auto-scaling is active → check **Container Instances Over Time** to see if instances are being added → if reservation is high but instances aren't scaling, check capacity provider configuration or ASG limits.

---

### # Service Connect - What is the request volume and error rate?

#### So what?
**Request Rate** and **HTTP Error Rate** are the primary application health signals when using Service Connect. **5xx Error Rate > 1%** sustained indicates application failures. **4xx errors** are usually client-side issues (broken callers, API changes). **Response Time** shows proxy-to-target latency — spikes correlate with CPU throttling or memory pressure. Watch out: All Service Connect metrics require Service Connect to be configured. HTTP metrics additionally require `appProtocol` in port mappings. If these metrics are absent, your services may use ALB instead — that's expected.

#### Now what?
Check **HTTP 5xx Error Rate** → if elevated, check **Response Time** for latency spikes → check **CPU/Memory Utilization** for resource pressure → check **Requests by Discovery Name** to isolate which endpoint is failing → check **TLS Errors** if connection failures appear.

---

## Part 3: Cause-Effect Triage Chains (22 chains)

1. If **Task Availability (%)** drops below 100% → check **Task Deficit** → check **Pending Tasks by Service** → likely causes: resource shortage, OOM kills, image pull failures → scale out service or fix task definition. (Confirmed)
2. If **Pending Tasks (count)** sustained > 0 → check **CPU/Memory Reservation** (EC2) → likely causes: cluster capacity exhausted, placement constraints unsatisfiable → add capacity or relax constraints. (Confirmed)
3. If **Restart Rate (/min)** climbing → check **Memory Utilization (%)** → if near 100%, OOM kills → increase task memory limits. (Confirmed)
4. If **Restart Rate (/min)** climbing but memory is fine → check application logs → likely causes: application crash, health check timeout, dependency failure. (Inference)
5. If **Active Deployments > 1** sustained → check **Task Deficit** → check **Restart Rate** → likely cause: new task revision failing to start, circuit breaker may trigger rollback. (Confirmed)
6. If **CPU Utilization (%)** sustained > 90% → check **Response Time** (Service Connect) → likely cause: CPU throttling causing latency → scale out service or increase CPU limits. (Mixed)
7. If **Memory Utilization (%)** > 85% sustained → check **Restart Rate** → if restarts start climbing, OOM kills are occurring → increase memory limits or investigate leaks. (Mixed)
8. If **CPU Used/Reserved (%)** low but **CPU Utilization (%)** high → tasks are using more than reserved (EC2 burst) → may need to set hard CPU limit or increase reservation. (Inference)
9. If **Memory Used/Reserved (%)** consistently > 90% → check **Restart Rate** → OOM imminent → increase memory hard limit in task definition. (Mixed)
10. If **Network In (MB/s)** drops to zero → check **Running Tasks** → if tasks are up, check network configuration (awsvpc mode, security groups, VPC endpoints). (Inference)
11. If **Network Out (MB/s)** spikes unexpectedly → check **Request Rate** (Service Connect) → likely causes: traffic surge, data transfer job, misconfigured egress. (Inference)
12. If **Storage I/O Rate (MB/s)** spiking → check **Ephemeral Storage (%)** → if ephemeral filling up, check log volume or temp files → likely cause: excessive logging or cache accumulation. (Inference)
13. If **Ephemeral Storage (%)** > 80% → check which services are affected → likely cause: log files not rotated, temp files not cleaned, large container images → increase ephemeral storage or fix cleanup. (Inference)
14. If **EBS Filesystem (%)** > 90% → check **EBS Filesystem Size** vs **EBS Utilized** → likely cause: persistent volume filling up → expand volume or clean data. (Inference)
15. If **CPU Reservation (%)** > 80% → check **Container Instances Over Time** → if instances not scaling, check ASG/capacity provider limits → add instances or enable capacity provider scaling. (Mixed)
16. If **Memory Reservation (%)** > 80% but CPU Reservation low → memory is the binding constraint → right-size tasks (reduce memory reservations on over-provisioned tasks) or add instances. (Inference)
17. If **HTTP 5xx Error Rate (%)** > 1% → check **Response Time** → check **CPU/Memory Utilization** → likely causes: application error, resource exhaustion, dependency failure. (Mixed)
18. If **HTTP 4xx Error Rate (%)** rising → check **Requests by Discovery Name** → likely causes: client-side bugs, API contract change, broken routing. (Inference)
19. If **Response Time (ms)** p95 spiking → check **CPU Utilization** → check **Active Connections** → likely causes: CPU throttling, connection exhaustion, downstream dependency slow. (Mixed)
20. If **Active Connections** spiking → check **New Connection Count** → if new connections also spiking, traffic surge → if new connections flat but active growing, connection leak. (Inference)
21. If **TLS Negotiation Errors** > 0 → check certificate expiry → check Service Connect TLS configuration → likely cause: expired or misconfigured certificates. (Inference)
22. If **Cluster Total Tasks** dropping but **Running Tasks** per service stable → standalone tasks or batch jobs completing → check if scheduled tasks are finishing normally. (Inference)

---

## Part 4: Operational Playbooks (8 playbooks)

### Playbook 1: Service Failing to Maintain Task Count
**Trigger:** Task Availability (%) < 100% sustained, Task Deficit > 0
**Decision rule:** If deficit persists > 5 minutes, investigate.
**Steps:**
1. Check **Task Availability (%)** and **Task Deficit** for scope (which services)
2. Check **Pending Tasks by Service** to find affected services
3. Check **Restart Rate by Service** — if climbing, containers are crash-looping
4. Check **Memory Utilization by Service** — if near 100%, likely OOM
5. Check **CPU Utilization by Service** — if near 100%, may be stuck
6. Check **Active Deployments** — if > 1, new deployment may be failing
7. Check **CPU/Memory Reservation** (EC2) — if near 100%, no room for new tasks
**Likely causes:** OOM kills, image pull failures, resource exhaustion, bad task definition, placement constraints
**Next actions:** Increase task memory/CPU limits, fix container image, add cluster capacity, check deployment circuit breaker status
**Label:** Mixed

### Playbook 2: Container Crash Loop
**Trigger:** Restart Rate (/min) > 0 sustained
**Decision rule:** Any sustained restarts warrant investigation.
**Steps:**
1. Check **Restart Rate by Service** to identify affected services
2. Check **Memory Utilization by Service** for the affected service
3. If memory high → OOM kills → increase task memory limits
4. If memory normal → application crash → check application logs
5. Check **Active Deployments** — may correlate with a bad deployment
6. Check **Task Deficit** — are tasks being replaced?
**Likely causes:** OOM, application bugs, dependency failures, health check timeouts
**Next actions:** Increase memory, roll back bad deployment, fix application, adjust health check timing
**Label:** Mixed

### Playbook 3: CPU Throttling / High Utilization
**Trigger:** CPU Utilization (%) > 90% sustained on a service
**Decision rule:** If correlated with latency increase or restarts, act.
**Steps:**
1. Check **Top Services by CPU (%)** to identify hottest services
2. Check **CPU: Utilized vs Reserved** for over/under-provisioning
3. Check **Response Time** (Service Connect) for latency impact
4. Check **Running vs Desired Tasks** — auto-scaling may already be responding
5. Check if this is Fargate (hard limit) vs EC2 (burst possible)
**Likely causes:** Under-provisioned CPU, traffic surge, inefficient code, memory GC pressure
**Next actions:** Increase task CPU limits, scale out service (more tasks), optimize application
**Label:** Mixed

### Playbook 4: EC2 Cluster Capacity Exhaustion
**Trigger:** CPU Reservation (%) or Memory Reservation (%) > 80%
**Decision rule:** If reservation trending up and capacity provider not scaling, investigate.
**Steps:**
1. Check **CPU & Memory Reservation Over Time** for trend
2. Check **Container Instances Over Time** — are instances being added?
3. Check **CPU Headroom (%)** and **Memory Headroom (%)** — which is lower?
4. Identify binding constraint (usually memory)
5. Check if capacity provider auto-scaling is configured
6. Check ASG max size — may have hit the ceiling
**Likely causes:** Traffic growth, over-reserved tasks, ASG max limit reached, capacity provider misconfiguration
**Next actions:** Increase ASG max, right-size task reservations, add capacity provider strategy
**Label:** Mixed

### Playbook 5: Deployment Stuck or Rolling Back
**Trigger:** Active Deployments > 1 sustained for longer than expected rollout time
**Decision rule:** If deployment count > 1 for > 15 minutes (adjust per service), investigate.
**Steps:**
1. Check **Active Deployments** — confirm > 1
2. Check **Task Deficit** — new tasks not reaching RUNNING?
3. Check **Restart Rate** — new revision crashing?
4. Check **Memory Utilization** — new revision OOM?
5. Check deployment circuit breaker status (ECS console / events)
6. Check **Running vs Desired** — is old deployment still serving?
**Likely causes:** Bad container image, insufficient resources, health check failing, dependency missing
**Next actions:** Roll back manually if circuit breaker hasn't triggered, fix image/config, increase resources
**Label:** Mixed

### Playbook 6: Service Connect High Error Rate
**Trigger:** HTTP 5xx Error Rate (%) > 1% sustained
**Decision rule:** If error rate is service-wide and sustained, escalate.
**Steps:**
1. Check **HTTP Response Codes Over Time** for pattern (gradual vs sudden)
2. Check **Requests by Discovery Name** to isolate affected endpoints
3. Check **Response Time** — errors often correlate with timeouts
4. Check **CPU/Memory Utilization** — resource exhaustion may cause errors
5. Check **Active Connections** — connection pool exhaustion?
6. Check **Restart Rate** — are backend tasks dying?
**Likely causes:** Application bugs, dependency failures, resource exhaustion, configuration errors
**Next actions:** Check application logs, roll back recent deployment, increase resources, check downstream dependencies
**Label:** Mixed

### Playbook 7: Network Throughput Anomaly
**Trigger:** Network In/Out (MB/s) drops to zero or spikes >3x baseline
**Decision rule:** If traffic pattern deviates significantly from normal, investigate.
**Steps:**
1. Check **Network Throughput (Rx vs Tx)** for pattern
2. Check **Running Tasks** — are tasks still up?
3. Check **Network In/Out by Service** to isolate affected service
4. Check **Request Rate** (Service Connect) — are requests still flowing?
5. Check security groups and network ACLs (outside dashboard scope)
**Likely causes:** Network misconfiguration, security group change, service outage, traffic rerouting
**Next actions:** Verify network configuration, check VPC flow logs, verify load balancer health
**Label:** Inference (relies on external data sources for root cause)

### Playbook 8: Storage Filling Up
**Trigger:** Ephemeral Storage (%) > 80% or EBS Filesystem (%) > 90%
**Decision rule:** If storage utilization is trending up toward limits, act before it hits 100%.
**Steps:**
1. Check **Ephemeral Storage: Utilized vs Reserved** for Fargate services
2. Check **EBS Filesystem (%)** for EBS-attached tasks
3. Check **Storage Read vs Write** — is write rate excessive?
4. Check **Storage I/O by Service** to identify which service
5. Check if log rotation is configured, temp files are being cleaned
**Likely causes:** Unrotated logs, temp file accumulation, cache growth, large artifacts
**Next actions:** Increase ephemeral storage in task definition, enable log rotation, clean temp files, expand EBS volume
**Label:** Inference


---

# AWS ECS — Caveats & Footguns

## High-Cardinality Dimensions to Avoid

- **[task-lifecycle-deployments, resource-utilization]** `TaskId` is very high cardinality (hundreds to thousands of unique values across a cluster). Never use as a group-by in timeseries or top-list widgets. Use `ServiceName` or `TaskDefinitionFamily` instead. ([AWS Container Insights Enhanced Observability](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-enhanced-observability-metrics-ECS.html))
- **[resource-utilization]** `ContainerInstanceId` is an ECS-internal reference. Prefer `InstanceId` (EC2InstanceId) for instance-level breakdowns — more recognizable in AWS console. (Inference)
- **[service-connect-traffic]** Combining `DiscoveryName` and `ServiceName` as simultaneous group-by levels can create cartesian explosion if many services talk to many endpoints. Use one dimension at a time. (Inference)

## Misleading Metrics and Wrong Aggregations

- **[resource-utilization]** `CPUUtilization` can **exceed 100%** on EC2 launch type when no hard CPU limit (`cpu` at task level) is set. Containers burst beyond their reservation. This is normal on EC2 but alarming if you expect 100% to be the ceiling. On Fargate, 100% is the hard ceiling. ([AWS Blog: How ECS manages CPU and memory](https://aws.amazon.com/blogs/containers/how-amazon-ecs-manages-cpu-and-memory-resources/))
- **[resource-utilization]** `MemoryUtilization` approaching 100% has different consequences per launch type. On Fargate it means OOM kill is imminent (hard limit). On EC2 with `memoryReservation` (soft limit) + `memory` (hard limit), the container can use memory up to the hard limit before being killed. Without a hard limit, the Linux kernel OOM killer decides. ([AWS ECS Task Definition Params](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html))
- **[capacity-scaling]** `CPUReservation` and `MemoryReservation` only count instances in ACTIVE or DRAINING status. Instances being launched by capacity providers are not counted until they register and become ACTIVE, causing a brief lag. (Inference based on [AWS ECS CloudWatch Metrics](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/available-metrics.html))
- **[resource-utilization]** Do NOT use `sum` aggregation for `CPUUtilization` or `MemoryUtilization` — these are already percentages. Summing them produces meaningless values. Use `average`, `min`, or `max`. ([AWS ECS CloudWatch Metrics](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/available-metrics.html))
- **[task-lifecycle-deployments]** `RestartCount` is monotonically increasing. Display it as a rate (per-second) not as a raw value — the raw value only goes up and provides no visual signal. (Inference)

## Unit Pitfalls

- **[resource-utilization]** `CpuUtilized` and `CpuReserved` are in **CPU units** (1024 units = 1 vCPU), NOT percentage. Don't confuse with `CPUUtilization` which IS a percentage. Display CPU units or convert to vCPU by dividing by 1024. ([AWS Container Insights Metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-ECS.html))
- **[resource-utilization]** `MemoryUtilized` and `MemoryReserved` are in **MiB** (mebibytes). Don't confuse with `MemoryUtilization` which is a percentage. Label charts clearly. ([AWS Container Insights Metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-ECS.html))
- **[network-io]** `NetworkRxBytes` and `NetworkTxBytes` from Container Insights are reported as **Bytes/Second** (already a rate). Do NOT apply `per-second` post-function — that would double-rate them. Use `average` aggregation with `none` post-function. ([AWS Container Insights Metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-ECS.html))
- **[storage-io]** `EphemeralStorageReserved` and `EphemeralStorageUtilized` are in **GB** (gigabytes), while `MemoryUtilized`/`MemoryReserved` are in MiB. Don't mix units in the same chart. ([AWS Container Insights Metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-ECS.html))
- **[service-connect-traffic]** `TargetResponseTime` is in **milliseconds**. Verify this in Stage 2 — some integrations may normalize to seconds. (Inference)

## Sampling/Temporality Pitfalls

- **[task-lifecycle-deployments, service-connect-traffic]** Counter metrics from CloudWatch (RestartCount, RequestCount, HTTPCode_*, StorageReadBytes, etc.) may be ingested into Tsuga as either delta or cumulative counters depending on the integration pipeline. This affects whether to use `per-second` (delta) or `rate` (cumulative) post-function. **Stage 2 discovery must verify temporality.** (Inference)
- **[resource-utilization]** CloudWatch `CPUUtilization` emits ~3 samples per minute (one every 20 seconds). The Average statistic is the most meaningful. Using Minimum or Maximum can be misleading for short-lived spikes within a single reporting period. ([AWS ECS CloudWatch Metrics](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/available-metrics.html))
- **[task-lifecycle-deployments]** `RunningTaskCount` and `DesiredTaskCount` are sampled at reporting intervals, not event-driven. Brief task failures between samples may not appear in the metrics. Use EventBridge for exact task lifecycle events. ([AWS ECS Task State Change Events](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_task_events.html))

## "This Looks Bad But Isn't"

- **[capacity-scaling]** `CPUReservation` or `MemoryReservation` at 0% on a cluster does NOT mean no work is running — it means no **EC2** tasks are running. Fargate tasks don't contribute to reservation metrics. If you use Fargate exclusively, reservation will always be 0% or absent. ([AWS ECS CloudWatch Metrics](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/available-metrics.html))
- **[task-lifecycle-deployments]** `DeploymentCount > 1` during a rolling update is normal. It only signals a problem if it persists well beyond the expected deployment duration. ([AWS ECS Service Deployments](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-types.html))
- **[task-lifecycle-deployments]** `PendingTaskCount > 0` during scale-out or deployment is normal. It's only concerning when sustained for minutes (placement failure or resource shortage). (Inference)
- **[network-io]** `NetworkRxBytes` = 0 for a service using `host` network mode is expected — the metric only works with `awsvpc` and `bridge` modes. Not an outage. ([AWS Container Insights Metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-ECS.html))

## Optional-Feature Traps

- **[task-lifecycle-deployments, resource-utilization, network-io, storage-io]** Container Insights is **disabled by default**. Without it, most Container Insights metrics (RunningTaskCount, PendingTaskCount, NetworkRxBytes, StorageReadBytes, CpuUtilized, etc.) are simply absent. This is the single most common reason for "missing data" on ECS dashboards. ([Setting up Container Insights on ECS](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/deploy-container-insights-ECS-cluster.html))
- **[service-connect-traffic]** All Service Connect metrics require Service Connect to be configured. If services use ALB + Cloud Map instead, the entire Service Connect section will have no data. This is expected, not broken. ([AWS ECS Service Connect](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect.html))
- **[service-connect-traffic]** HTTP status code metrics (`HTTPCode_Target_*`) and `RequestCount` require `appProtocol` to be set in the task definition port mapping. Without it, Service Connect still works but only provides byte-level and connection-level metrics. ([AWS ECS Available Metrics](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/available-metrics.html))
- **[storage-io]** `EphemeralStorageReserved` and `EphemeralStorageUtilized` are **Fargate only** (Linux platform 1.4.0+). On EC2 launch type these metrics will not exist. ([AWS Container Insights Metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-ECS.html))
- **[capacity-scaling]** `GPUReservation` only appears on EC2 clusters with GPU instances. If no GPU instances are registered, this metric will be absent. ([AWS ECS CloudWatch Metrics](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/available-metrics.html))


---

