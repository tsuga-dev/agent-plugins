# Kubernetes Integration Context Bundle

## Metadata

**Technology:** Kubernetes
**Deployment:** self-hosted
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** mixed (OTel — kubeletstats + k8scluster receivers)
**Integration scope:** core service only
**Primary use-case:** reliability and performance

---

## How to use this bundle

- `01_kubernetes_metrics.csv` — Source of truth for all metrics: names, units, temporality, safe aggregations, group-bys, and Tsuga field mappings.
- `02_kubernetes_dashboard_plan.yaml` — Dashboard plan: sections, widgets, derived signals, explanation notes, triage chains, and playbooks.
- `03_kubernetes_state.yaml` — Machine-readable state: stage status, unknowns, assumptions, and log intel for Stage 4.
- `04_kubernetes_memory.md` — Human-readable Stage 1 summary: key assumptions, tradeoffs, and what Stage 2 must verify first.
- Stage 2 will create `05_kubernetes_metric_catalog.csv` as the discovered metric catalog (confirmed names + attribute keys + curated descriptions).
- Stage 4 should read `00` "Log intelligence (Stage 4 handoff)" and `03.log_intel` first before designing log routes.

---

## What it is and what "good" looks like

### Confirmed by sources

Kubernetes is an open-source container orchestration platform that automates deployment, scaling, and lifecycle management of containerized workloads. Metrics are emitted by two OpenTelemetry receivers: `kubeletstats` (per-node/pod/container resource usage from the kubelet API) and `k8scluster` (cluster-state counts from the Kubernetes API: replicas, phases, conditions). [OTel kubeletstats receiver docs](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/kubeletstatsreceiver), [OTel k8scluster receiver docs](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/k8sclusterreceiver)

**"Good" looks like:**
- All pods in Running phase; zero in Pending for >5 minutes; Failed count at baseline (near zero)
- Container restarts at a steady low baseline (<3/day for healthy services)
- All nodes in Ready condition; no NotReady nodes
- CPU limit utilization < 70%; memory limit utilization < 80% (headroom for spikes)
- Deployment desired == available for all production workloads
- DaemonSet coverage 100% (every eligible node is scheduled)
- Node filesystem < 70% used (eviction threshold is typically 85%)

**Paging intent:** Page on pod crash loops (restart rate sudden spike), node NotReady (condition_ready = 0), sustained Pending pods (scheduler can't place work), or deployment replicas unavailable.

**Top 3 incident shapes:**
1. **OOMKill cascade** → start with "CPU & Memory" section: memory limit utilization > 100% → container restarts → pod phase Failed
2. **Node disk pressure eviction** → start with "Storage" section: filesystem utilization > 85% → pods evicted → Running Pod Ratio drops
3. **Deployment rollout stuck** → start with "Workloads" section: Unavailable Replicas > 0 for >5min → Pod Phase by Deployment shows pending/failed pods

### Best-practice inference

- Control plane metrics (kube-apiserver, etcd, scheduler) are not covered in this integration — they require Prometheus scraping of component endpoints and are out of scope for the OTel-based integration. [Inference — standard OTel scope boundary]
- StatefulSet state metrics (desired/current/ready/updated pods) are not currently flowing into Tsuga (k8scluster receiver not deployed or misconfigured). StatefulSet workloads can still be observed via pod-level metrics (pod phase, container restarts, resource usage). [Inference from analysis — receiver config gap]

---

## Key concepts

### Glossary

| Term | Definition | Operational meaning | Dashboard section |
|------|-----------|---------------------|-------------------|
| Pod | Smallest schedulable unit; 1+ containers sharing network/storage | A "broken" pod shows as phase=Failed or restart loop | cluster-health |
| Container | Runtime unit inside a pod; has its own resource limits | CPU/memory limits trigger throttling or OOMKill | cpu-memory |
| Node | Worker machine in the cluster (VM or bare metal) | NotReady node = workloads can't run there | nodes |
| Namespace | Logical grouping of resources; multi-tenancy boundary | High restarts in one namespace = team-level issue | cluster-health |
| Deployment | Declares desired pod count + rollout strategy | Unavailable replicas = partial degradation | workloads |
| ReplicaSet | Controller maintaining exact pod count for a Deployment | desired - available = unhealthy pod gap | workloads |
| DaemonSet | Ensures one pod per (matching) node | Coverage < 100% = some nodes unprotected | workloads |
| StatefulSet | Deployment for stateful apps (ordered, stable identity) | State metrics not flowing — observe via pod metrics | workloads |
| Job | Run-to-completion task; creates pods that terminate when done | Failed pods = job didn't complete | jobs |
| CronJob | Scheduled Jobs | active_jobs count growing = stuck previous runs | jobs |
| kubelet | Node agent that manages pod lifecycle on each node | Source of all kubeletstats metrics | nodes |
| k8scluster receiver | OTel receiver polling the Kubernetes API server | Source of replica counts, pod phase, conditions | workloads |
| kubeletstats receiver | OTel receiver polling the kubelet `/stats/summary` API | Source of CPU/memory/network/filesystem metrics | nodes, cpu-memory |
| Nanocores | CPU unit: 1 core = 1,000,000,000 nanocores | Raw unit of k8s.*.cpu.usage — large numbers | cpu-memory |
| Resource Limit | Hard cap on CPU/memory a container can use | Exceeding memory limit → OOMKill; CPU limit → throttle | cpu-memory |
| Resource Request | Soft reservation used by scheduler for placement | Requests >> limits = node overcommit risk | cpu-memory |
| Node Condition | Status flags: Ready, MemoryPressure, DiskPressure, PIDPressure | Ready=false = node unavailable | nodes |
| Eviction | Kubelet forcibly terminates pods under resource pressure | Triggered at filesystem > 85% or memory pressure | storage |
| Taint/Toleration | Node taints repel pods unless they have matching toleration | Misscheduled daemonset nodes = taint mismatch | workloads |
| CrashLoopBackOff | Pod restarts repeatedly with exponential backoff | Application crashes; check pod logs | cluster-health |
| OOMKill | Out-of-memory: container exceeds memory limit | Memory limit utilization > 100% transiently | cpu-memory |
| Phase | Pod lifecycle state: Pending/Running/Succeeded/Failed/Unknown | Only Running is healthy for long-running services | cluster-health |
| Allocatable | Node resources available for pod scheduling (capacity minus OS/kubelet overhead) | Used to compute actual utilization headroom | nodes |

### Concept Map

```
Cluster -> contains -> Node (why: nodes are the execution substrate for all workloads)
Node -> runs -> kubelet (why: kubelet manages pod lifecycle and exposes kubeletstats metrics)
Node -> has -> Condition (Ready/MemoryPressure/DiskPressure) (why: conditions gate pod scheduling)
Deployment -> manages -> ReplicaSet (why: rolling updates create new RS, phase out old RS)
ReplicaSet -> controls -> Pod (why: RS ensures desired pod count is maintained)
DaemonSet -> creates -> Pod per node (why: node-level agents like log collectors run via DaemonSet)
Pod -> runs on -> Node (why: scheduler places pods on nodes with sufficient allocatable resources)
Pod -> contains -> Container (why: containers share network namespace within a pod)
Container -> has -> ResourceRequest + ResourceLimit (why: requests drive scheduling; limits enforce caps)
Container -> consumes -> CPU/memory from Node allocatable pool (why: total container requests must fit within node allocatable)
CronJob -> spawns -> Job (why: CronJob is the scheduler; Job is the execution unit)
Job -> creates -> Pod (why: job work runs inside pods that terminate on completion)
container.cpu.usage (nanocores) -> feeds -> CPU Limit Utilization % derived signal (why: utilization = usage/limit)
k8s.node.memory.usage -> relative to -> k8s.node.allocatable_memory (why: utilization = usage/allocatable, not capacity)
k8s.pod.phase -> aggregated by -> k8s.namespace.name (why: phase breakdown per namespace shows team-level health)
k8s.container.restarts (cumulative) -> rising rate -> CrashLoopBackOff symptom (why: restarts are the OTel proxy for crash loops)
k8s.deployment.desired - k8s.deployment.available -> Unavailable Replicas signal (why: gap = degraded replicas)
k8s.daemonset.desired_scheduled_nodes - k8s.daemonset.current_scheduled_nodes -> scheduling gap (why: gap = nodes without the daemonset pod)
k8s.node.network.io (cumulative) -> rate() -> bandwidth in/out (why: cumulative bytes need rate for per-second throughput)
k8s.node.filesystem.usage / k8s.node.filesystem.capacity -> Filesystem Utilization % (why: raw bytes meaningless without context of total)
Node DiskPressure condition -> triggers -> pod eviction (why: kubelet evicts pods when disk is full)
Node MemoryPressure condition -> triggers -> pod eviction (why: kubelet evicts pods when memory is exhausted)
```

### Entities and dimensions

| Dimension | Why useful | Cardinality risk | Safe top-N |
|-----------|-----------|-----------------|-----------|
| `context.k8s.cluster.name` | Multi-cluster comparison | Low (typically 1-20 clusters) | 10 |
| `context.k8s.namespace.name` | Team/application boundary | Medium (10-100 namespaces) | 20 |
| `context.k8s.node.name` | Node-level triage | Medium (10-500 nodes) | 20 |
| `context.k8s.pod.name` | Per-pod investigation | HIGH — do NOT use as primary group-by in overview; use in deep dive top-lists only | 20 |
| `context.k8s.container.name` | Container-level breakdown | Medium (bounded by workload count) | 20 |
| `context.k8s.deployment.name` | Deployment health | Low-medium | 20 |
| `context.k8s.daemonset.name` | DaemonSet status | Low | 20 |
| `context.k8s.replicaset.name` | ReplicaSet health | Medium (old RS kept during rollouts) | 20 |
| `context.k8s.job.name` | Job tracking | Low-medium | 20 |
| `context.k8s.cronjob.name` | CronJob tracking | Low | 20 |
| `context.direction` | Network I/O direction (receive/transmit) | Fixed (2 values) — safe for group-by | 2 |
| `context.state` | CPU state (idle/user/system/iowait/steal...) / Memory state | Fixed (5-8 values) — safe for group-by | 8 |
| `context.k8s.pod.status.phase` | Pod phase breakdown | Fixed (5 values: Running/Pending/Failed/Succeeded/Unknown) | 6 |
| `context.env` | Environment separation | Fixed (2-5 values) | 5 |
| `context.team` | Team ownership | Low (10-50 teams) | 20 |

**Do NOT group-by:** `context.k8s.pod.name` in timeseries for large clusters (causes 100s of series). Use top-list widgets for pod-level breakdowns instead.

### Tsuga field mapping

**Confirmed by sources:** `context.env` and `context.team` are confirmed in `.env`.

**Best-practice inference (OTel → context.* naming convention, must be verified in Stage 2):**

| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|--------------------------|--------------------------|----------------------|
| `k8s.cluster.name` | `context.k8s.cluster.name` | must-exist (all k8s metrics) |
| `k8s.namespace.name` | `context.k8s.namespace.name` | must-exist (pod/workload metrics) |
| `k8s.node.name` | `context.k8s.node.name` | must-exist (node + kubeletstats metrics) |
| `k8s.pod.name` | `context.k8s.pod.name` | must-exist (pod-level metrics) |
| `k8s.container.name` | `context.k8s.container.name` | must-exist (container-level metrics) |
| `k8s.deployment.name` | `context.k8s.deployment.name` | optional (workload metrics) |
| `k8s.daemonset.name` | `context.k8s.daemonset.name` | optional (daemonset metrics) |
| `k8s.replicaset.name` | `context.k8s.replicaset.name` | optional (replicaset metrics) |
| `k8s.statefulset.name` | `context.k8s.statefulset.name` | optional (not flowing yet) |
| `k8s.job.name` | `context.k8s.job.name` | optional (job metrics) |
| `k8s.cronjob.name` | `context.k8s.cronjob.name` | optional (cronjob metrics) |
| `direction` (network I/O) | `context.direction` | must-exist (network I/O metrics) |
| `state` (CPU/memory) | `context.state` | must-exist (system.cpu.utilization, system.memory.*) |
| `k8s.pod.status.phase` | `context.k8s.pod.status.phase` | must-exist (k8s.pod.phase metric) |
| `env` | `context.env` | must-exist (from .env) |
| `team` | `context.team` | must-exist (from .env) |

---

## Golden signals

### Traffic (throughput)

**What it means for Kubernetes:** Network I/O (bytes/s in and out) at node and pod level. Application-level request throughput is not in scope here — it requires application-specific instrumentation.

**Degradation causes:** unusual pod-to-pod chatting, log floods, large data transfers, misconfigured sidecar proxies.

**Best telemetry:** `k8s.node.network.io`, `k8s.pod.network.io` (cumulative sums → use `rate()`)

**Section questions:** Is node/pod network I/O within normal ranges? Are any pods dominating network usage?

### Errors

**What it means for Kubernetes:** Container restarts (proxy for crash loops), pod phase failures, network errors, and failed job pods.

**Degradation causes:** application bugs (OOMKill, unhandled exceptions), image pull errors, misconfigured resource limits, broken network policies, disk full.

**What people page on:** sustained container restart rate spike (CrashLoopBackOff), pods stuck in Failed phase, Unavailable Replicas > 0.

**Best telemetry:** `k8s.container.restarts` (cumulative → `rate()` or `increase()`), `k8s.pod.phase` (filter phase:failed), `k8s.job.failed_pods`, `k8s.node.network.errors`

**Section questions:** Are container restart rates spiking? Are pods in Failed/Pending phase? Are jobs completing successfully?

### Latency

**What it means for Kubernetes:** At the platform level, "latency" manifests as pod scheduling delay (time pods spend in Pending), not request latency (which is application-level). CPU throttling from limit hits indirectly increases response times.

**Best telemetry:** Pod phase timeseries (Pending count over time); CPU limit utilization (> 90% = throttling).

**Section questions:** How long are pods staying in Pending? Are containers hitting CPU limits?

**Confirmed by sources:** CPU throttling from cgroup limit enforcement is a well-documented Kubernetes behavior. [Kubernetes resource limits docs](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

**Best-practice inference:** Scheduling latency (time to transition from Pending to Running) is not directly exposed as an OTel metric. Pod phase timeseries is the best available proxy.

### Saturation

**What it means for Kubernetes:** Node-level resource saturation (CPU, memory, disk) determines whether new pods can be scheduled and whether existing pods will be evicted. Container-level saturation (usage vs limit) determines throttling and OOMKill risk.

**Degradation causes:** memory overcommit (requests << limits), log volume filling node disks, noisy neighbor pods.

**What people page on:** Node MemoryPressure or DiskPressure condition (precursor to eviction), memory limit utilization > 90% across many pods.

**Best telemetry:** `k8s.node.memory.usage / k8s.node.allocatable_memory`, `k8s.node.filesystem.usage / k8s.node.filesystem.capacity`, `container.memory.usage / k8s.container.memory_limit`, `k8s.node.condition_ready`

**Section questions:** Are node memory/filesystem utilizations approaching eviction thresholds? Are containers near their limits?

---

## Telemetry sources

| Source type | How collected | What it provides | Pros | Cons | Common "no data" meaning |
|------------|--------------|-----------------|------|------|--------------------------|
| OTel `kubeletstats` receiver | Polls kubelet `/stats/summary` API on each node | CPU/memory/network/filesystem usage at node, pod, container granularity | Rich resource usage; includes nanocores, bytes, network I/O | No cluster-state counts (replicas, phases); CPU metrics in nanocores (hard to read) | Receiver not deployed or wrong node RBAC |
| OTel `k8scluster` receiver | Polls Kubernetes API server | Pod phase, container readiness, replica counts, conditions, resource requests/limits | Cluster-state truth; captures Pending/Failed pods | Doesn't include resource usage (only config values) | Receiver not deployed or API server RBAC missing |
| `system.*` metrics | Host-level OTel `hostmetrics` receiver (or kubeletstats node-level) | Node CPU utilization by state, memory by state | Familiar % format; useful for node CPU utilization | May be emitted per-pod/per-container in Kubernetes context — groupBy carefully | Hostmetrics receiver not deployed |

**Optional features that change metric availability:**
- `k8s.pod.memory.node.utilization` (kubeletstats): requires `k8s_api_config` + explicit opt-in in receiver config
- `k8s.node.allocatable_cpu` (k8scluster): requires `allocatable_types_to_report: [cpu]` in receiver config
- StatefulSet metrics: require k8scluster receiver to be deployed (currently not flowing)

**Confirmed by sources:** OTel kubeletstats and k8scluster receiver documentation. [kubeletstats](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/kubeletstatsreceiver) [k8scluster](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/k8sclusterreceiver)

**Best-practice inference:** The `hostmetrics` receiver may run alongside the Kubernetes receivers for node-level `system.*` metrics. The exact deployment topology varies by organization.

---

## Log intelligence (Stage 4 handoff)

### Confirmed by sources

**Log sources matrix:**

| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|--------|------------|----------------|---------------------------|---------|
| Container stdout/stderr | Kubelet log driver → fluentd/fluent-bit → Tsuga | Kubernetes log line with metadata prefix OR raw app log | Unstructured (depends on app) | Kubernetes logging docs |
| Kubernetes audit log | API server → configurable audit sink | JSON structured | Structured JSON | Kubernetes audit log docs |
| Kubelet system log | Node journald or /var/log/kubelet.log | Go log format (key=value style) | Semi-structured | Kubernetes node logs docs |
| kube-system pods | Container stdout (scheduler, controller-manager) | Go log format or structured JSON | Mixed | Standard k8s component logs |

**Known log formats:**

Format 1 — Kubernetes container log (containerd/CRI format):
```
2024-01-15T10:30:00.123456789Z stdout F {"level":"info","msg":"request processed","method":"GET","path":"/health","status":200,"duration_ms":5}
```
- Fields: `timestamp` (RFC3339 nanoseconds), `stream` (stdout/stderr), `flags` (F=full line, P=partial), `message` (rest of line)
- Timestamp: RFC3339 with nanoseconds
- JSON application logs are common but NOT guaranteed — depends on the application

Format 2 — Kubernetes container log (Docker legacy format):
```
{"log":"INFO: Starting up server on port 8080\n","stream":"stdout","time":"2024-01-15T10:30:00.123456789Z"}
```
- JSON wrapper with `log`, `stream`, `time` fields

Format 3 — Go structured log (kube-system components):
```
I0115 10:30:00.123456 1 server.go:123] "Starting controller" name="deployments"
```
- Format: `<level><month><day> <time> <PID> <file>:<line>] <message> [<key>=<value>]*`
- Level: `I`=info, `W`=warning, `E`=error, `F`=fatal

**Candidate query filters for Stage 4:**
- **Precise (recommended):** `context.k8s.namespace.name:* AND NOT context.k8s.namespace.name:kube-system` — targets application namespace logs
- **Fallback:** `source:kubernetes` or `context.k8s.pod.name:*` — all pod logs including system
- **Rationale:** Starting with application namespaces avoids noisy kube-system component logs. The risk is missing monitoring-agent log routes.

**Attribute mapping hints:**

| Raw field | Suggested Tsuga key | Confidence | Notes |
|-----------|---------------------|-----------|-------|
| Timestamp from log content | `timestamp` | High | Override ingest timestamp when present |
| `stream` (stdout/stderr) | `context.k8s.stream` | Medium | Informational only |
| Kubernetes `level`/`severity` | `severity` | High | Map to Tsuga log level |
| Application `log.level`/`level` | `severity` | High | Most JSON app logs use this key |
| Application `msg`/`message` | `body` | High | Standard log body field |
| Application `method` | `context.http.method` | High | HTTP access log field |
| Application `path`/`url` | `context.http.path` | High | HTTP access log field |
| Application `status`/`status_code` | `context.http.status_code` | High | HTTP access log field |
| Application `duration`/`duration_ms` | `context.duration_ms` | Medium | Varies by app |
| Application `error`/`err` | `context.error` | Medium | Error context |
| `k8s.pod.name` (from metadata) | `context.k8s.pod.name` | High | Set by k8s attribute processor |
| `k8s.namespace.name` (from metadata) | `context.k8s.namespace.name` | High | Set by k8s attribute processor |

**Parsing risks:**
- Multi-line logs (Java stack traces, Python tracebacks) split across multiple CRI log entries — requires multiline aggregation before parsing
- Escaped quotes in JSON payloads within the log field
- Mixed formats in the same namespace: some pods emit JSON, others emit plaintext
- Partial lines (`flags=P`) indicate multi-line logs split at buffer boundaries
- Timezone: all k8s log timestamps are UTC (RFC3339Z), but some applications embed local timestamps

### Best-practice inference

Kubernetes log routing in Tsuga will depend on whether the k8s attribute processor is configured in the OTel collector pipeline (it enriches logs with k8s.pod.name, k8s.namespace.name, etc. as resource attributes). Without the attribute processor, `context.k8s.*` fields will be absent from logs and the query filters above won't work.

---

## Caveats and footguns

- **[cpu-memory]** CPU usage metrics (`k8s.node.cpu.usage`, `k8s.pod.cpu.usage`, `container.cpu.usage`) are reported in **nanocores** (1 core = 10^9 nanocores). Raw numbers look enormous. Normalizer should use `custom: ncores` or derive cores by dividing by 1e9 — but Tsuga formulas don't support division by large literals cleanly. Use the numbers as-is for comparison widgets, and document the unit. (Confirmed — OTel kubeletstats receiver spec)

- **[cpu-memory]** `k8s.container.cpu_limit` and `k8s.container.memory_limit` are **resource specs from the Pod definition**, not real-time consumption. A container can be within its limit while being heavily throttled. Always pair limit values with actual usage metrics. (Confirmed — Kubernetes resource model docs)

- **[cluster-health]** `k8s.container.restarts` is a **cumulative counter** (total restarts since container start). The raw value always goes up. To detect restart rate spikes, use `rate()` or `increase()` with a short window. Do NOT display raw restart count as a "current health" QV — it will look alarming even for stable containers with historical restarts. (Confirmed — OTel k8scluster receiver spec)

- **[cluster-health]** `k8s.pod.phase` reports one data point per pod per active phase. The value is 1 for the active phase, 0 for others (depending on receiver config). **Do not sum all phases** — it will double or triple-count pods. Filter by `context.k8s.pod.status.phase:Running` to count running pods specifically. Stage 2 must verify the exact phase attribute field name. (Inference from OTel spec)

- **[nodes]** `k8s.node.allocatable_memory` is memory allocatable for pods (total capacity minus OS/kubelet overhead). Using `k8s.node.allocatable_memory` as denominator for memory utilization is more accurate than using raw capacity. However, `k8s.node.allocatable_cpu` is **not flowing** (optional metric not enabled) — CPU utilization % at node level requires `system.cpu.utilization` as a proxy. (Confirmed from analysis)

- **[workloads]** StatefulSet state metrics (`k8s.statefulset.*`) are **not flowing** into Tsuga. StatefulSet workloads must be observed via pod-level metrics: pod phase by label selector, container restarts, and resource usage. Section widgets for StatefulSets are gated. (Confirmed from analysis — receiver config gap)

- **[network]** `k8s.node.network.io` and `k8s.pod.network.io` are **cumulative sums** (total bytes transferred since container/node start). Always use `rate()` for per-second bandwidth. Never display raw bytes in a timeseries — the value will spike vertically at container restarts due to counter reset handling. (Confirmed — OTel kubeletstats spec)

- **[network]** Network I/O metrics have a **`direction` attribute** (receive/transmit). When computing "total I/O", use a formula summing both directions. When computing receive/transmit separately, use query-level filters. Avoid grouping by direction in a timeseries without filtering — the receive and transmit lines will be on the same chart by default. (Confirmed — OTel receiver spec)

- **[storage]** `container.filesystem.usage` is **not flowing** into Tsuga (kubeletstats receiver config issue). Pod filesystem usage (`k8s.pod.filesystem.usage`) is available as a partial substitute but is at pod level, not container level. Container filesystem available (`container.filesystem.available`) IS available. (Confirmed from analysis)

- **[storage]** The Kubernetes default eviction hard threshold is **85% filesystem** usage (configurable via kubelet `--eviction-hard`). Node filesystem utilization > 85% means kubelet will start evicting pods. This is the critical threshold, not a "warning" signal. (Confirmed — Kubernetes eviction docs)

- **[jobs]** `k8s.job.failed_pods` counts **pods that failed within a job**, not job failures per se. A single job can have multiple failed pod attempts before succeeding (backoffLimit). Do not equate "failed pods > 0" with "job failed" — some retries are expected. (Confirmed — Kubernetes Job docs)

- **[jobs]** `k8s.cronjob.active_jobs` counts **currently running job instances** spawned by a CronJob. A value > 1 often indicates previous runs haven't completed before the next schedule — check `spec.concurrencyPolicy`. (Confirmed — Kubernetes CronJob docs)

- **[workloads]** During a **rolling update**, `k8s.deployment.available` < `k8s.deployment.desired` is **expected and temporary**. Don't alert on this pattern unless it persists beyond the expected rollout duration. The deep dive "Unavailable Replicas" widget will show this dip — include it in the explanation note. (Confirmed — Kubernetes rolling update docs)

- **[workloads]** `k8s.daemonset.misscheduled_nodes` > 0 means daemonset pods are running on **nodes they shouldn't** (taint/toleration mismatch). This is different from "not scheduled on nodes where they should run" which is `desired - current`. Both are relevant but indicate different failure modes. (Confirmed — Kubernetes DaemonSet docs)

- **[cpu-memory]** Kubernetes CPU requests/limits are **per-container**, but kubeletstats reports CPU usage at node, pod, and container granularity. When comparing pod-level CPU usage to container-level CPU limits, be mindful that a multi-container pod aggregates CPU from all its containers. (Inference)

- **[nodes, cpu-memory]** Memory metrics include several variants: `memory.usage`, `memory.rss`, `memory.working_set`. **RSS (Resident Set Size)** is actual physical memory. **Working Set** is RSS + file-backed memory not reclaimable under pressure. Kubernetes uses **working_set** (container.memory.working_set) as the metric for limit enforcement, not `usage`. If available, use working_set for memory limit utilization. (Confirmed — Kubernetes memory management docs)

- **[cluster-health, cpu-memory]** A container in **CrashLoopBackOff** shows as Running (it's restarting), not Failed. The signal is `k8s.container.restarts` rising. Pod phase=Failed only appears before kubelet restarts it. Do not rely solely on pod phase for crash loop detection. (Confirmed — Kubernetes pod lifecycle docs)

- **[nodes]** `k8s.node.condition_ready` has a value of 1 when the node is Ready and 0 when it is NotReady. Summing across all nodes gives "count of Ready nodes". A sudden drop is an incident-level signal. (Inference from OTel spec — exact value semantics must be confirmed in Stage 2)

- **[cpu-memory]** CPU requests (`k8s.container.cpu_request`) are in **nanocores** just like CPU usage. A request of 250m (250 millicores) is stored as 250,000,000 nanocores in the metric. The same unit scale applies to limits. (Confirmed — Kubernetes resource model)

- **[cluster-health]** Pod phases `Succeeded` and `Unknown` are not health indicators for long-running services (they indicate completed or lost-contact states). Only `Running` and the absence of `Pending`/`Failed` matter for service health. Batch workloads (Jobs) have `Succeeded` as the target terminal state. (Confirmed — Kubernetes pod lifecycle docs)

- **[workloads]** The `k8s.replicaset.available` metric reports **ready replicas**, not just running pods. A pod can be Running but not Ready if its readiness probe fails. `available` < `desired` in a ReplicaSet means traffic is being dropped. (Confirmed — Kubernetes ReplicaSet docs)

- **[all sections]** All k8s metrics carry the `k8s.cluster.name` attribute. **Always include `context.k8s.cluster.name` as a global dashboard filter** for multi-cluster deployments. Without it, metrics from all clusters are summed, making cluster-specific anomalies invisible. (Confirmed — OTel k8s attribute conventions)

---

## Confirmed Tsuga prefixes

- `k8s.*` — **CONFIRMED** (34+ metrics present in Tsuga including k8s.pod.phase, k8s.container.restarts, k8s.node.network.io, k8s.node.memory.usage, k8s.deployment.desired/available, k8s.daemonset.*, k8s.job.*, k8s.node.condition_ready — verified via live Tsuga metric enumeration in the analysis document dated 2026-03-11)
- `container.*` — **CONFIRMED** (container.memory.rss, container.memory.usage, container.cpu.usage, container.filesystem.available, container.filesystem.capacity present in Tsuga — same analysis)
- `system.*` — **CONFIRMED** (system.cpu.utilization with state attribute, system.memory.usage confirmed mapped — same analysis)

---

## Discovery status

Discovery: not yet performed (deferred to Stage 2). Pre-analysis document provides strong metric coverage mapping from live Tsuga enumeration (3286 total metrics, all 4 pages paginated, dated 2026-03-11).

**Anticipated counts per prefix based on pre-analysis:**
- `k8s.*` — ~34+ confirmed metrics
- `container.*` — ~8+ metrics
- `system.*` — ~5+ metrics

---

## Top sources

1. https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/kubeletstatsreceiver — kubeletstats receiver: exact metric names, units, temporality (Sum vs Gauge), and attribute keys
2. https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/k8sclusterreceiver — k8scluster receiver: cluster-state metrics (phases, replicas, conditions, requests/limits)
3. https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/ — Kubernetes resource requests and limits: semantics, enforcement, OOMKill and throttling behavior
4. https://kubernetes.io/docs/concepts/workloads/controllers/deployment/ — Deployment rolling update mechanics: desired vs available vs updated replicas
5. https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/ — Node eviction thresholds: filesystem and memory pressure conditions, default eviction thresholds
6. https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/ — Pod phases: Running/Pending/Failed/Succeeded/Unknown semantics, CrashLoopBackOff context
7. https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/ — Kubernetes metrics pipeline: kubelet summary API, metrics-server, resource vs custom metrics
8. https://opentelemetry.io/docs/specs/semconv/k8s/ — OTel semantic conventions for Kubernetes: canonical resource attribute names (k8s.cluster.name, k8s.namespace.name, etc.)
9. https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/ — DaemonSet scheduling: desired vs scheduled vs misscheduled semantics, taint/toleration interaction
10. https://kubernetes.io/docs/concepts/workloads/controllers/job/ — Job and CronJob lifecycle: failed pod retry semantics, backoffLimit, concurrencyPolicy
