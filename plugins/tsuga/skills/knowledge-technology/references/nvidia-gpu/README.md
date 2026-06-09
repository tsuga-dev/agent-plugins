# NVIDIA Integration Context Bundle

## Metadata
**Technology:** NVIDIA (DCGM GPU telemetry surface)
**Deployment:** self-hosted
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** mixed
**Integration scope:** core service only
**Primary use-case:** reliability and performance

## How to use this bundle
- Use `01_nvidia_metrics.csv` as the source of truth for metric names, units, temporality guidance, and safe query construction.
- Use `02_nvidia_dashboard_plan.yaml` to build both dashboards (sections, widgets, derived signals, notes, triage chains, playbooks, and coverage map).
- Use `03_nvidia_state.yaml` for machine-readable assumptions, unknowns, log-intel status, and stage status.
- Use `04_nvidia_memory.md` for a concise human handoff of Stage 1 decisions and Stage 2 priority checks.
- Stage 2 creates `05_nvidia_metric_catalog.csv` as the discovered metric inventory with curated descriptions and attribute-key hygiene.
- Stage 4 should read this file's `## Log intelligence (Stage 4 handoff)` and `03_nvidia_state.yaml` `log_intel` before creating log routes.

## What it is and what "good" looks like

### Confirmed by sources
- NVIDIA DCGM is the canonical telemetry surface for datacenter GPU fleet monitoring, and `dcgm-exporter` exposes DCGM fields as Prometheus-style metrics with labels like GPU UUID, device, pod, namespace, and container in Kubernetes environments. [S1][S2][S3]
- The supplied integration metric set spans utilization, clocks, thermals, memory capacity, PCIe/NVLink transport, power/energy, remap health, vGPU license status, and Xid fault signals. [S2][S3]
- Xid values are driver-reported GPU error identifiers that appear in kernel logs and require follow-up context; the value alone is a starting point, not a root cause. [S6][S7][S8]
- Good operational posture means sustained compute throughput without thermal/power throttling, low transport retries, stable memory headroom, and no growth in remap-failure or severe Xid signals. [S3][S4][S9]
- For dashboard-first triage, the highest-value first split is: (1) faults/reliability, (2) saturation/thermals/power, then (3) transport bottlenecks and workload shape. [S3][S4][S9]

### Best-practice inference
- **Incident shape 1: Thermal or power clamp before hard fault**
  - Pattern: `DCGM_FI_DEV_GPU_UTIL` drops while `DCGM_FI_DEV_GPU_TEMP` and `DCGM_FI_DEV_POWER_USAGE` stay elevated.
  - First section: `saturation-power-encoding`.
- **Incident shape 2: Fabric/PCIe path degradation**
  - Pattern: transport throughput shifts (`DCGM_FI_PROF_PCIE_*`, `DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL`) plus replay growth (`DCGM_FI_DEV_PCIE_REPLAY_COUNTER`).
  - First section: `throughput-io-fabric`.
- **Incident shape 3: Memory health deterioration**
  - Pattern: remapped-row counters trend upward or `DCGM_FI_DEV_ROW_REMAP_FAILURE` flips true.
  - First section: `errors-reliability` then `capacity-memory`.
- High-level paging intent for this integration: detect degraded GPU service quality early, classify whether the limiter is workload demand vs hardware health vs platform configuration, and route responders to the right owning team quickly.

## Key concepts

### Confirmed by sources
- DCGM field IDs define metric semantics directly (for example temperature, clocks, utilization, replay, remapped rows, power, energy). [S3]
- `dcgm-exporter` provides ready-made metric families and allows profiling counters to be included for transport/throughput visibility. [S1][S2][S4]
- Xid events come from driver/kernel log paths and must be correlated with workload and hardware context during triage. [S6][S7]

### Best-practice inference
- The safest integration model is to treat GPU as a bounded compute appliance: observe utilization demand, thermal/power constraints, memory pressure, and transport path efficiency together.
- For shared clusters, dashboards should emphasize per-GPU hotspot and per-workload slice behavior, while avoiding unbounded process-level group-bys in top-level views.

### Glossary

| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| DCGM | NVIDIA Data Center GPU Manager telemetry and management stack | Canonical metric semantics for this integration | availability-health |
| dcgm-exporter | Prometheus exporter exposing DCGM field IDs | Main metric ingestion path | availability-health |
| GPU Utilization | Fraction of cycles with active compute | Demand proxy for compute workload pressure | saturation-power-encoding |
| SM Clock | Streaming multiprocessor clock frequency | Performance ceiling indicator for compute kernels | performance-thermals-clocks |
| Memory Clock | HBM/GDDR clock frequency | Memory bandwidth capability indicator | performance-thermals-clocks |
| GPU Temperature | Core device temperature | Thermal health and throttling risk signal | performance-thermals-clocks |
| Memory Temperature | Memory subsystem temperature | Memory thermal risk and stability signal | performance-thermals-clocks |
| Power Usage | Instant power draw in watts | Power cap pressure and efficiency context | saturation-power-encoding |
| Total Energy Consumption | Cumulative energy usage | Workload energy cost trend and efficiency basis | saturation-power-encoding |
| Frame Buffer Used | Consumed framebuffer memory | Immediate memory pressure indicator | capacity-memory |
| Frame Buffer Free | Remaining framebuffer memory | Headroom and capacity runway indicator | capacity-memory |
| Mem Copy Util | Memory-copy engine utilization | Data-movement bottleneck indicator | capacity-memory |
| Encoder Util | NVENC utilization | Video/transcoding pipeline load indicator | saturation-power-encoding |
| Decoder Util | NVDEC utilization | Decode pipeline load indicator | saturation-power-encoding |
| PCIe TX Bytes | PCIe transmit throughput counter/rate | Host-to-device/device-to-host path characterization | throughput-io-fabric |
| PCIe RX Bytes | PCIe receive throughput counter/rate | Transport asymmetry and bottleneck diagnosis | throughput-io-fabric |
| PCIe Replay Counter | PCIe retransmission/replay signal | Link integrity degradation early warning | errors-reliability |
| NVLink Bandwidth Total | Aggregate NVLink transfer bandwidth metric | Peer/fabric transport demand indicator | throughput-io-fabric |
| Xid Error | Driver-reported GPU fault identifier | Fault triage starting point requiring catalog lookup | errors-reliability |
| Correctable Remapped Rows | Count of rows remapped after correctable errors | Memory reliability trend signal (degrades over time) | errors-reliability |
| Uncorrectable Remapped Rows | Count of rows remapped after uncorrectable errors | Higher-severity memory health degradation signal | errors-reliability |
| Row Remap Failure | Flag indicating remap failure condition | Immediate risk marker for hardware health escalation | errors-reliability |
| vGPU License Status | License state for virtual GPU environments | Feature/performance degradation risk in vGPU stacks | availability-health |
| MIG | Multi-Instance GPU partitioning model | Dimension/cardinality driver for per-slice visibility | capacity-memory |

### Concept Map

```text
Client or batch scheduler -> places workload on -> GPU-backed node (why: determines initial demand distribution)
GPU-backed node -> hosts -> one or more physical GPUs (why: capacity and fault domain boundary)
Physical GPU -> reports via -> DCGM field IDs (why: canonical health/performance semantics)
DCGM field IDs -> exported by -> dcgm-exporter (why: metrics become queryable in Tsuga)
GPU utilization -> depends on -> SM clock and workload mix (why: low clock can cap realized throughput)
Memory copy utilization -> competes with -> compute kernels for bandwidth (why: copy pressure can lower effective throughput)
Frame buffer used -> reduces -> free memory headroom (why: low headroom predicts allocation failures or slowdown)
Memory temperature -> rises with -> sustained memory traffic (why: memory subsystem can become bottleneck)
GPU temperature -> rises with -> compute and power draw (why: thermal limits can trigger performance drop)
Power usage -> constrained by -> board/system power policy (why: power limit can clamp clocks before faults)
Total energy consumption -> accumulates with -> workload runtime (why: supports efficiency and cost proxy analysis)
PCIe TX/RX throughput -> reflects -> host-device data movement pattern (why: transport imbalance identifies I/O bottlenecks)
PCIe replay counter -> indicates -> link quality/retransmission issues (why: replay growth can explain latency and throughput loss)
NVLink bandwidth total -> indicates -> GPU-to-GPU or fabric exchange demand (why: peer-traffic-heavy jobs depend on NVLink quality)
Remapped row counters -> capture -> memory reliability degradation over time (why: predicts escalating hardware risk)
Row remap failure flag -> signals -> inability to remediate memory faults (why: escalates toward maintenance/isolation)
Xid error value -> appears in -> kernel logs (why: critical fault breadcrumb for incident triage)
Xid catalog lookup -> maps code to -> likely subsystem and action bucket (why: narrows next operational step)
vGPU license status -> controls -> full virtual GPU feature/performance state (why: licensing failures can look like performance incidents)
Service ownership metadata -> maps to -> context.team and context.env filters (why: on-call routing and blast-radius control)
Kubernetes labels (pod/namespace/container) -> map to -> context.k8s.* keys (why: workload attribution and noisy-neighbor analysis)
MIG profile/instance dimensions -> map to -> context.gpu.mig.* keys (why: per-slice saturation triage in partitioned GPUs)
```

### Entities and dimensions

| Entity/Dimension | Why useful | Cardinality risk | Safe top-N | Do NOT group-by guidance |
|---|---|---|---|---|
| `context.env` | Production vs non-production split | Low | 5 | Keep as global filter, not per-widget split in overview |
| `context.team` | Ownership routing | Low | 10 | Avoid as first split for hardware root-cause widgets |
| `context.service.name` | Workload/service attribution | Medium | 20 | Avoid combining with pod UID or process IDs |
| `context.uuid` | Stable GPU identity in this Tsuga dataset | Medium | 20 | Preferred primary GPU split key |
| `context.gpu` | GPU device index label from exporter | Medium | 20 | Use with `context.hostname` for human triage clarity |
| `context.hostname` | Node hotspot identification | Medium | 20 | Prefer node-level before pod-level keys |
| `context.device` | Device identifier emitted by exporter | Medium | 20 | Avoid combining with many high-card keys in overview |
| `context.modelname` | Hardware cohort segmentation | Low | 10 | Keep coarse and avoid per-pod joins |
| `context.pci_bus_id` | Hardware path identity for fault triage | Medium | 20 | Use in deep-dive; avoid top-level KPI splits |
| `context.scope` | Stable scope fallback dimension | Medium | 20 | Prefer when service-level grouping is noisy |
| `context.deployment.environment` | Deployment-level environment label | Low | 10 | Keep secondary to `context.env` to avoid duplicate filters |
| `context.service.instance.id` | Instance-level process identity | High | 20 | Deep-dive only |
| `context.k8s.namespace.name` | Tenant/workload partition | Medium | 20 | Not observed in current Tsuga metrics; verify before use |
| `context.k8s.pod.name` | Pod-level hotspot/root-cause | High | 20 | Not observed in current Tsuga metrics; deep-dive only if later available |
| `context.container.name` | Container-level attribution | High | 20 | Not observed in current Tsuga metrics; avoid as default split |

### Tsuga field mapping

| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| `Hostname` | `context.hostname` | Optional (confirmed in current Tsuga dataset) |
| `gpu` (device index label) | `context.gpu` | Optional (confirmed) |
| `UUID` | `context.uuid` | Optional (confirmed and recommended primary GPU key) |
| `modelName` / product name | `context.modelname` | Optional (confirmed) |
| `device` label | `context.device` | Optional (confirmed) |
| PCI bus id | `context.pci_bus_id` | Optional (confirmed) |
| scope label | `context.scope` | Optional (confirmed fallback dimension) |
| deployment env label | `context.deployment.environment` | Optional (confirmed; secondary to `context.env`) |
| `pod` | `context.k8s.pod.name` | Optional (not observed in current Tsuga metrics) |
| `namespace` | `context.k8s.namespace.name` | Optional (not observed in current Tsuga metrics) |
| `container` | `context.container.name` | Optional (not observed in current Tsuga metrics) |
| service tag from pipeline | `context.service.name` | Optional (confirmed and recommended for workload ownership) |
| environment tag | `context.env` | Must-exist (confirmed in current Tsuga dataset) |
| team tag | `context.team` | Must-exist (confirmed in current Tsuga dataset) |

## Golden signals

### Confirmed by sources
| Signal | What it means for NVIDIA GPU operations | Best telemetry sources | Typical degradation causes | What people page on | Section questions |
|---|---|---|---|---|---|
| Traffic | GPU work entering compute and data paths | `DCGM_FI_DEV_GPU_UTIL`, `DCGM_FI_DEV_MEM_COPY_UTIL`, `DCGM_FI_PROF_PCIE_TX_BYTES`, `DCGM_FI_PROF_PCIE_RX_BYTES`, `DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL` [S2][S3] | Workload spikes, data-loader imbalance, host I/O bottlenecks | Sustained high util with dropping throughput or rising retries | Is demand compute-bound, memory-bound, or transport-bound? |
| Errors | Hardware/driver reliability faults that degrade workload quality | `DCGM_FI_DEV_XID_ERRORS`, remap counters, replay counter, remap failure [S3][S6][S7] | Driver issues, unstable links, memory degradation, hardware faults | New high-severity Xid events, remap growth, replay surges | Are we seeing transient faults or persistent hardware degradation? |
| Latency | Effective time-to-complete behavior implied by clocks/transport constraints | SM/mem clocks, thermals, replay counter, PCIe/NVLink metrics [S2][S3][S4] | Thermal clamp, power cap, link retransmits, memory pressure | Throughput drop with stable demand and rising thermal/power stress | Is latency from compute throttling or data transport contention? |
| Saturation | How close GPUs are to compute, memory, power, and media-engine limits | Utilization, frame buffer used/free, power usage, encoder/decoder util [S2][S3] | Oversubscription, poor placement, concurrent media + compute jobs | Persistent >90% utilization with shrinking memory headroom | Which resource is first limiter for the affected workload cohort? |

### Best-practice inference
- For GPU fleets, **errors and saturation are usually more actionable than raw traffic** because utilization alone can look healthy while quality is collapsing.
- Treat transport metrics (`PCIE_*`, `NVLINK_*`, replay) as first-class when debugging distributed training or inference pipelines with heavy host-device movement.
- Pair each golden-signal panel with an ownership dimension (`context.team` or `context.service.name`) to keep triage handoffs fast.

## Telemetry sources

### Confirmed by sources
| Source type | How collected | What it provides | Pros/cons | Common pitfalls |
|---|---|---|---|---|
| DCGM Exporter default counters | `dcgm-exporter` exposing `DCGM_FI_*` families | Core GPU thermals, clocks, util, power, memory, reliability fields | Broad coverage and standard names; requires compatible DCGM + driver stack | Assuming all optional counters are enabled by default [S1][S2] |
| DCGM profiling counters | Profiling metrics enabled via exporter include list | PCIe/NVLink throughput and advanced performance counters | High diagnostic value for transport bottlenecks; may need explicit include set and can increase overhead | Missing profile metrics interpreted as zero instead of disabled [S1][S4] |
| NVIDIA Xid logs | Kernel logs (`NVRM: Xid`) and catalog mapping | Fault event IDs and diagnostic context | Essential for fault triage; code alone is not root cause | Treating any single Xid as deterministic hardware failure without context [S6][S7][S8] |
| GPU Operator telemetry path | Kubernetes packaging of DCGM exporter + labels/logs | Practical deployment defaults and troubleshooting hooks | Faster onboarding in k8s; version coupling with operator/driver | Label key drift across environments and upgrades [S5][S10] |

### Best-practice inference
- If `DCGM_FI_PROF_*` series are absent, start with a missing-feature hypothesis (counter set not enabled) before assuming transport is idle.
- In mixed bare-metal + Kubernetes estates, normalize dimensions early (`host`, `gpu.uuid`, `team`, `env`) to keep cross-environment dashboards comparable.
- Keep process-level or pod-level dimensions out of overview unless incident context explicitly requires them.

## Log intelligence (Stage 4 handoff)

### Confirmed by sources

| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|---|---|---|---|---|
| NVIDIA driver Xid logs | Linux kernel log (`/var/log/messages`, `/var/log/syslog`, journal) | `NVRM: Xid (bus-id): <code>, <details>` | Unstructured text | Xid documentation shows exact sample and grep pattern [S7] |
| dcgm-exporter / GPU Operator component logs | Container logs in Kubernetes | Logrus-like text (`time="..." level=info msg="..."`) | Semi-structured text | GPU Operator troubleshooting log snippets [S5] |

Known log formats:
1. **NVIDIA Xid line**
   - Sample:
     - `[...] NVRM: GPU at 0000:03:00: GPU-b850f46d-d5ea-c752-ddf3-c4453e44d3f7`
     - `[...] NVRM: Xid (0000:03:00): 14, Channel 00000001` [S7]
   - Shape notes: driver prefix, GPU GUID context line, then Xid code line.
   - Timestamp pattern: syslog/journal timestamp prefix from host logger.
   - Optional fields: channel, additional tokens vary by Xid.
2. **dcgm-exporter operational log line**
   - Sample: `time="2024-03-04T16:49:03Z" level=info msg="Starting webserver"` [S5]
   - Shape notes: key-value segments with quoted values.
   - Timestamp pattern: RFC3339 value inside `time="..."`.
   - Optional fields: message text and component details vary.

Candidate query filters for Stage 4:
- Precise: `context.service.name:samples-nvidia AND (message:*Xid* OR message:*dcgm-exporter*)`
  - Rationale: user-provided service tag plus NVIDIA fault/exporter markers.
  - Risk: misses renamed service streams or nonstandard message bodies.
- Fallback: `context.service.name:samples-nvidia`
  - Rationale: guaranteed broad catch-all for the tagged stream.
  - Risk: high noise; requires split processors by log shape.

Attribute mapping hints:

| Raw field | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| syslog timestamp | `timestamp` | High | Usually already parsed upstream |
| `GPU-<uuid>` token | `context.uuid` | High | Stable correlation key in current Tsuga dataset |
| PCIe bus id (`0000:03:00`) | `context.pci_bus_id` | Medium | Useful for host-level hardware mapping |
| Xid numeric code | `error.code` | High | Keep numeric for catalog lookup |
| Xid details text (`Channel 00000001`) | `error.details` | High | Preserve raw suffix for debugging |
| logrus `level=` | `level` | High | Map to canonical log level |
| logrus `msg=` | `message` | High | Use as base text field |

Parsing risks:
- Kernel log prefixes vary by distro/log driver (journal vs rsyslog).
- Xid lines can appear with/without prior GPU GUID line in same ingestion window.
- Mixed log streams under one service tag require split conditions to avoid false parses.
- Quoted logrus payloads may contain escaped quotes and variable key order.

### Best-practice inference
- Stage 4 should ship two parser branches: one for `NVRM: Xid` and one for logrus `key="value"` style lines.
- Preserve original message and parsed `error.code` together; do not drop raw text because Xid interpretation often needs surrounding context.

## Caveats and footguns
- **[availability-health]** `DCGM_FI_DEV_VGPU_LICENSE_STATUS` is meaningful only in vGPU deployments; physical GPU estates can show missing data by design. (Inference)
- **[availability-health]** A healthy license status does not imply healthy compute performance; it only confirms entitlement state. [S10]
- **[performance-thermals-clocks]** Clock metrics can fall during thermal or power management events without explicit fault counters changing. [S3][S4]
- **[performance-thermals-clocks]** Temperature alone is insufficient; combine with util and power before classifying throttling. (Inference)
- **[performance-thermals-clocks]** Memory temperature can diverge from core temperature; track both to avoid false negatives. [S3]
- **[throughput-io-fabric]** `DCGM_FI_PROF_PCIE_TX_BYTES` and `DCGM_FI_PROF_PCIE_RX_BYTES` semantics can appear as rate-like gauges or byte counters depending on pipeline/exporter handling; Stage 2 must confirm temporality. [S2][S3]
- **[throughput-io-fabric]** `DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL` presence depends on hardware topology and enabled profiling/collection paths. [S2][S4]
- **[throughput-io-fabric]** Low PCIe throughput is not always bad; it can indicate compute-heavy kernels with resident data. (Inference)
- **[errors-reliability]** `DCGM_FI_DEV_XID_ERRORS` exposes code values, not full root cause; consult Xid catalog and surrounding logs. [S6][S8]
- **[errors-reliability]** A single transient Xid may not require host drain, but recurring identical high-severity Xids usually do. (Inference)
- **[errors-reliability]** Remapped-row counters are long-lived health indicators; short-window rates can hide serious cumulative drift. [S3]
- **[errors-reliability]** `DCGM_FI_DEV_ROW_REMAP_FAILURE` should be treated as high severity even if utilization remains normal. [S3]
- **[errors-reliability]** PCIe replay counter increases can reflect link quality issues unrelated to model code changes. [S3][S9]
- **[capacity-memory]** `FB_USED` can remain high after warmup while workload is healthy; trend and eviction/failure symptoms matter more than absolute peak. (Inference)
- **[capacity-memory]** `FB_FREE` may fluctuate rapidly with allocator behavior; avoid paging on brief dips without utilization/fault corroboration. (Inference)
- **[capacity-memory]** MIG partitions change apparent memory ceilings; compare within same MIG profile when possible. [S1]
- **[capacity-memory]** `MEM_COPY_UTIL` spikes can indicate input pipeline backpressure instead of GPU underperformance. (Inference)
- **[saturation-power-encoding]** High encoder or decoder utilization can coexist with low compute utilization; media pipelines require separate triage from CUDA-heavy jobs. [S2]
- **[saturation-power-encoding]** Power usage near cap can mask as software slowdown; pair with clock/utilization patterns before escalating app teams. [S3][S4]
- **[saturation-power-encoding]** Total energy is cumulative; query-value snapshots without rate/increase transformation can be misleading. [S2]
- **[saturation-power-encoding]** Aggregate GPU-level utilization can hide one-hot hotspots; use top-list by `context.uuid` in deep dive. (Inference)
- **[throughput-io-fabric, errors-reliability]** Missing profiling metrics should trigger "feature not enabled" messaging, not hard failure alarms. [S1][S4]

## Confirmed Tsuga prefixes
- `DCGM_FI_DEV_*` — **CONFIRMED** (19 metrics discovered in Tsuga over the last 24 hours).
- `DCGM_FI_PROF_*` — **CONFIRMED** (2 metrics discovered in Tsuga over the last 24 hours).
- `DCGM_EXP` family was not observed in Tsuga during Stage 2 preflight and is excluded from active discovery prefixes for this bundle.

## Discovery status
Discovery: completed in Stage 2. 21/21 Stage 1 metrics were confirmed in Tsuga, 0 were missing, and 0 unexpected NVIDIA metrics were discovered under the active prefixes. Counter temporality was confirmed as cumulative for all seven counter metrics, and group-by keys were corrected to discovered context fields (`context.uuid`, `context.hostname`).

## Top sources
- [S1] https://docs.nvidia.com/datacenter/dcgm/latest/gpu-telemetry/dcgm-exporter.html - Official exporter behavior, labels, profiling enablement guidance, and deployment notes.
- [S2] https://raw.githubusercontent.com/NVIDIA/dcgm-exporter/main/etc/default-counters.csv - Canonical exported metric name list plus exporter-provided help text and metric types.
- [S3] https://docs.nvidia.com/datacenter/dcgm/latest/dcgm-api/dcgm-api-field-ids.html - Authoritative field semantics for clocks, temperatures, power, memory health, replays, and vGPU status.
- [S4] https://docs.nvidia.com/datacenter/dcgm/latest/user-guide/feature-overview.html - Profiling metric feature constraints and operational caveats.
- [S5] https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/troubleshooting.html - Real-world GPU Operator / exporter log examples and troubleshooting context.
- [S6] https://docs.nvidia.com/deploy/xid-errors/index.html - Root documentation set for Xid meaning and triage model.
- [S7] https://docs.nvidia.com/deploy/xid-errors/working-with-xid-errors.html - Exact Xid log format examples and collection location guidance.
- [S8] https://docs.nvidia.com/deploy/xid-errors/analyzing-xid-catalog.html - Current Xid catalog for code interpretation and action classification.
- [S9] https://docs.nvidia.com/datacenter/dcgm/latest/user-guide/dcgm-diagnostics.html - Diagnostic rules tying replay counts, clocks, and Xids to failure conditions.
- [S10] https://docs.nvidia.com/ai-enterprise/release-6/latest/infra-software/vgpu/licensing.html - Current vGPU licensing behavior and operational consequences of licensing state.
