# AWS EFS Integration Context Bundle

## Metadata
**Technology:** AWS EFS
**Deployment:** managed
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** mixed
**Integration scope:** core service only
**Primary use-case:** reliability and performance

## How to use this bundle
- Use `01_aws-efs_metrics.csv` as the source of truth for metric names, units, temporality assumptions, and safe query patterns.
- Use `02_aws-efs_dashboard_plan.yaml` as the implementation blueprint for sections, widgets, derived signals, explanation notes, triage chains, and playbooks.
- Use `03_aws-efs_state.yaml` as the machine-readable state file for stage status, inferred namespace mappings, log intelligence status, and unresolved unknowns.
- Use `04_aws-efs_memory.md` for the human-readable Stage 1 handoff narrative and Stage 2 priority checks.
- Stage 2 will create `05_aws-efs_metric_catalog.csv` as the discovered inventory and reconciliation memory for actual Tsuga metric and attribute coverage.
- Stage 4 should read `00` under `Log intelligence (Stage 4 handoff)` and `03.log_intel` before attempting log route creation.

## What it is and what "good" looks like

### Confirmed by sources
- Amazon EFS is a managed NFS file system for EC2, containers, and other AWS compute that exposes health primarily through CloudWatch metrics around throughput, I/O composition, storage size, client connections, throughput headroom, and optional replication lag. [S1][S2][S3][S6]
- The core operational posture is shaped by file system type (Regional vs One Zone), performance mode (General Purpose vs Max I/O legacy), and throughput mode (Elastic, Provisioned, or Bursting). Those choices directly change what "good" throughput headroom looks like and whether burst credits matter. [S3][S4]
- Good for EFS means client connections are stable, metered throughput stays comfortably below permitted throughput, `PercentIOLimit` does not pin near the General Purpose limit, storage growth is expected across Standard and cold tiers, and replication lag remains near the documented 15-minute RPO envelope when replication is enabled. [S2][S3][S6]
- The fastest dashboard split for incidents is: headroom pressure (`fleet-health`), workload shape change (`throughput-mix`), unexpected storage growth or tiering drift (`storage-lifecycle`), and DR freshness risk (`replication-resilience`).

### Best-practice inference
- Incident shape 1: **Throughput ceiling or credit exhaustion.** Start in `fleet-health`; check `I/O Limit Utilization`, `Throughput Utilization`, `Burst Credit Balance`, then `Permitted Throughput`.
- Incident shape 2: **Workload pattern changed.** Start in `throughput-mix`; compare `Metadata Throughput`, `Metadata Read vs Write`, and `Metered vs Total Throughput` to tell metadata-heavy churn from broader file throughput pressure.
- Incident shape 3: **Storage bill or cold-data movement surprise.** Start in `storage-lifecycle`; determine whether total bytes are growing in Standard or whether IA and Archive shares changed after lifecycle policy edits.
- Incident shape 4: **Disaster recovery freshness risk.** Start in `replication-resilience`; `TimeSinceLastSync` is the only high-signal service metric if replication exists.
- A useful EFS dashboard is narrower than a database or queue dashboard: EFS exposes file-system service counters, not application latency, per-directory hot spots, or rich server-side error codes. Logs and client-side telemetry are needed for mount failures and NFS semantics problems.

## Key concepts

### Glossary

| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| EFS file system | Managed NFS storage service in AWS | Main blast-radius boundary for all service metrics | all |
| FileSystemId | Unique identifier for one EFS file system | Primary safe group-by for fleet views | all |
| DestinationFileSystemId | Replica destination file system id | Required to interpret replication lag by pair | replication-resilience |
| Regional file system | EFS file system replicated across multiple AZs in one Region | Default durability posture for production | fleet-health |
| One Zone file system | EFS file system stored in one AZ | Lower resilience; storage and DR sections matter more | fleet-health |
| General Purpose mode | Default EFS performance mode with lower latency | Only mode where `PercentIOLimit` meaningfully indicates limit pressure | fleet-health |
| Max I/O mode | Older high-parallelism mode with higher latency | `PercentIOLimit` can be absent or less relevant; higher latency may be expected | fleet-health |
| Elastic throughput | Throughput mode that scales automatically with workload | Burst credits do not accrue or drain here | fleet-health |
| Provisioned throughput | Fixed configured throughput independent of file system size | `PermittedThroughput` becomes a contractual capacity signal | fleet-health |
| Bursting throughput | Throughput mode tied to Standard storage size plus credits | `BurstCreditBalance` becomes a runway signal | fleet-health |
| Burst credits | Accumulated capacity that lets bursting-mode EFS exceed baseline throughput | Falling credits mean future throttling risk before current outage | fleet-health |
| PermittedThroughput | Maximum throughput the file system can currently drive | Best denominator for utilization math | fleet-health |
| MeteredIOBytes | Throughput-accounted bytes after EFS read discount rules | Best numerator for throughput headroom | throughput-mix |
| TotalIOBytes | Actual bytes processed without read discount | Separates true load from billing-weighted load | throughput-mix |
| DataReadIOBytes | Bytes read from the file system | Read workload volume | throughput-mix |
| DataWriteIOBytes | Bytes written to the file system | Write workload volume and write pressure | throughput-mix |
| MetadataIOBytes | Bytes used by metadata operations | High values often mean directory traversal or metadata-heavy workloads | throughput-mix |
| MetadataReadIOBytes | Bytes from metadata reads | Explains read-heavy namespace scans | throughput-mix |
| MetadataWriteIOBytes | Bytes from metadata writes | Explains create/unlink/chmod style metadata churn | throughput-mix |
| PercentIOLimit | Percent of the General Purpose I/O limit consumed | Early warning that latency pain is limit-driven | fleet-health |
| ClientConnections | Number of connected clients | Useful blast-radius and mount-fanout indicator | fleet-health |
| StorageBytes | File system size across storage classes | Capacity and cost proxy metric | storage-lifecycle |
| EFS Standard | Hot SSD-backed storage class | Growth here affects bursting baseline and cost | storage-lifecycle |
| EFS IA | Infrequent Access storage class | Rising share suggests lifecycle policy is moving cold data | storage-lifecycle |
| EFS Archive | Coldest EFS storage class | Useful for cost posture, but not for latency-sensitive data | storage-lifecycle |
| IASizeOverhead | Metering overhead from 128 KiB minimum billing in IA | Large overhead means many tiny cold files | storage-lifecycle |
| ArchiveSizeOverhead | Metering overhead from 128 KiB minimum billing in Archive | Large overhead means Archive is inefficient for small files | storage-lifecycle |
| TimeSinceLastSync | Seconds since the last successful replication sync | Direct DR freshness signal | replication-resilience |
| Close-to-open consistency | EFS/NFS consistency model | Explains app complaints that do not show as service-level EFS faults | throughput-mix |
| Mount helper | `amazon-efs-utils` client tool | Stage 4 log source for mount failures and TLS/watchdog issues | replication-resilience |

[S2][S3][S4][S5][S6][S7][S8]

### Concept Map
Client workload -> mounts -> EFS file system (why: all service metrics aggregate at file-system scope)
EC2 instance or pod -> creates -> NFS client connection (why: `ClientConnections` is often the first fanout signal)
Application read path -> drives -> DataReadIOBytes (why: read throughput is a core demand shape)
Application write path -> drives -> DataWriteIOBytes (why: write throughput is the clearest mutation signal)
Directory traversal and stat-heavy code -> drives -> MetadataReadIOBytes (why: namespace scans can hurt without large data throughput)
Create/delete/chmod-heavy code -> drives -> MetadataWriteIOBytes (why: metadata churn is operationally distinct from data writes)
DataReadIOBytes + DataWriteIOBytes + MetadataIOBytes -> contribute to -> TotalIOBytes (why: total workload shape matters)
Read discount rules -> transform -> MeteredIOBytes (why: metered throughput is what counts against throughput limits)
MeteredIOBytes -> compared against -> PermittedThroughput (why: this reveals throughput utilization)
Bursting throughput mode -> consumes -> BurstCreditBalance (why: credit drain predicts future throughput pressure)
Standard storage growth -> increases -> bursting baseline throughput (why: larger hot footprint raises baseline)
Elastic throughput mode -> removes dependence on -> BurstCreditBalance (why: credit-based reasoning becomes misleading)
General Purpose mode -> constrained by -> I/O limit (why: `PercentIOLimit` signals limit proximity)
Max I/O mode -> trades -> higher latency for more parallelism tolerance (why: low-level latency expectations change)
Lifecycle management -> moves data from -> Standard to IA and Archive (why: storage mix shifts cost and latency posture)
Small cold files -> inflate -> IA and Archive overhead dimensions (why: `StorageBytes` meter can rise faster than actual bytes)
Regional file system -> replicates durability across -> multiple AZs (why: higher resilience baseline)
One Zone file system -> concentrates risk in -> single AZ (why: replication and backup posture matter more)
Replication configuration -> synchronizes source -> destination file system (why: DR depends on successful syncs)
TimeSinceLastSync -> indicates -> replica freshness debt (why: failover usefulness depends on this lag)
Mount helper -> emits -> client-side logs (why: service metrics do not explain mount failures)
CloudWatch Logs mount-status integration -> captures -> mount success or failure events (why: Stage 4 can route mount attempts)
context.env and context.team -> scope -> ownership and blast radius (why: filters should match oncall routing)
context.cloud.region -> separates -> regional fleet posture (why: EFS is regional, and replication may span regions)
context.filesystemid -> anchors -> per-file-system triage (why: safest entity key for widgets)
context.destinationfilesystemid -> anchors -> replication pair attribution (why: one source can have one or more replication relationships)

### Entities and dimensions

| Entity or dimension | Why useful | Cardinality risk | Safe top-N suggestion | Do NOT group-by guidance |
|---|---|---|---|---|
| `FileSystemId` | Primary EFS identity and safest drilldown axis | Low | 10 | Default group-by for almost every fleet widget |
| `DestinationFileSystemId` | Distinguishes replication pairs | Low | 10 | Use only on replication widgets |
| `context.env` | Separates prod and non-prod posture | Low | 6 | Must exist as a global filter |
| `context.team` | Maps ownership and routing | Low | 12 | Must exist as a global filter |
| `context.cloud.region` | Distinguishes regional fleets and DR topology | Low | 10 | Useful global filter and fleet split |
| `context.cloud.account.id` | Separates accounts or tenants | Low | 10 | Good optional global filter |
| `StorageClass` or equivalent | Required for `StorageBytes` Standard/IA/Archive analysis | Low | 6 | Do not assume exact key name until Stage 2 confirms it |
| Throughput mode | Changes whether burst credits matter | Low | 4 | Treat as optional metadata; do not make it a primary chart split unless confirmed |
| Performance mode | Explains `PercentIOLimit` relevance | Low | 3 | Optional metadata, not a first-line filter |
| File system type | Regional vs One Zone resilience posture | Low | 3 | Optional metadata, not a high-frequency split |
| Availability Zone | Useful only for One Zone inventory context | Medium | 6 | Avoid in core metric widgets unless emitted |
| Mount target id | Helpful for networking or mount-target diagnostics | Medium | 10 | Do not assume it exists on service metrics |
| Client host or pod | Useful for mount-failure logs, not service metrics | High | 10 | Do not use as a metric group-by by default |
| Access point id | Can isolate application tenancy patterns | Medium | 10 | Useful only if actually emitted; otherwise avoid |
| NFS operation or path | Would be powerful for app diagnosis | Very High | 0 | Do not expect on EFS service metrics |

### Tsuga field mapping

| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| `FileSystemId` | `context.filesystemid` | Confirm in Stage 2 |
| `DestinationFileSystemId` | `context.destinationfilesystemid` | Unknown in this workspace; verify in Stage 3 only if replication metrics appear |
| Storage class dimension (`Total`, `Standard`, `IA`, `Archive`, overhead variants) | `context.storageclass` | Confirmed in Stage 2 |
| AWS Region | `context.cloud.region` | Confirmed in Stage 2 |
| AWS Account ID | `context.cloud.account.id` | Confirmed in Stage 2 |
| Performance mode | `context.performance_mode` | Optional |
| Throughput mode | `context.throughput_mode` | Optional |
| File system type (`Regional`, `One Zone`) | `context.file_system_type` | Optional |
| Org environment enrichment | `context.env` | Confirmed in Stage 2 |
| Org team enrichment | `context.team` | Confirmed in Stage 2 |

### Confirmed by sources
- AWS documents `FileSystemId` as the core dimension for all EFS metrics and `DestinationFileSystemId` as the additional dimension for `TimeSinceLastSync`. [S2][S6]
- `StorageBytes` is emitted with storage-class dimensions that distinguish `Total`, `Standard`, `IA`, `IASizeOverhead`, `Archive`, and `ArchiveSizeOverhead`. [S2]

### Best-practice inference
- Stage 2 confirmed flat lowercase keys in this workspace, including `context.filesystemid` and `context.storageclass`.
- Throughput mode and performance mode metadata were not discovered on live metrics, so those concepts stay in note text rather than dashboard filters.

## Golden signals

### Confirmed by sources
| Signal | What it means for AWS EFS | Typical degradation causes | Best telemetry sources | What people page on | Section questions |
|---|---|---|---|---|---|
| Traffic | Actual file-system throughput plus metadata intensity | App demand spike, backup/scan jobs, deploy-induced metadata storms | `TotalIOBytes`, `MeteredIOBytes`, `MetadataIOBytes`, `MetadataReadIOBytes`, `MetadataWriteIOBytes` [S2] | Throughput jumps or metadata share changes unexpectedly | Is traffic higher, and is it metadata-heavy? |
| Errors | EFS service metrics do not expose rich error counts; failures are usually seen as mount issues or app-side NFS errors | mount helper failures, network path issues, security groups, TLS setup, stale NFS clients | mount helper logs, mount attempt CloudWatch Logs, support logs [S7][S8][S9] | Mount attempts failing or clients unable to connect | Is this a service headroom issue or a client-side mount issue? |
| Latency | Best inferred from headroom and mode because EFS service metrics expose throughput and I/O limit more directly than per-op latency | hitting General Purpose I/O limit, credit depletion, Max I/O mode expectations, cold-storage access expectations | `PercentIOLimit`, `PermittedThroughput`, `BurstCreditBalance`, performance mode context [S2][S3] | `PercentIOLimit` pinned high with user-visible slowness | Is slowness caused by I/O limit pressure or workload shape? |
| Saturation | Headroom exhaustion in throughput or burst-credit runway | bursting credits draining, metered throughput near permitted ceiling, unexpected client fanout | `MeteredIOBytes`, `PermittedThroughput`, `BurstCreditBalance`, `ClientConnections` [S2][S3] | Throughput utilization sustained high or credit runway collapsing | Which limit is closest to failing right now? |

### Best-practice inference
- `MeteredIOBytes` compared with `PermittedThroughput` is more actionable than raw byte totals alone because it encodes EFS read discounts and actual limit pressure.
- `MetadataIOBytes` is often the overlooked signal that explains "EFS is slow" reports when the app is doing directory-walks, file-stat storms, or lots of tiny-file operations.
- For EFS, logs and client telemetry are more important for "errors" than service metrics; an empty error widget would be misleading, so the dashboard should treat mount logs as Stage 4 scope instead.

## Telemetry sources

### Confirmed by sources
| Source type | How collected | What it provides | Pros/cons | Common pitfalls |
|---|---|---|---|---|
| EFS CloudWatch metrics | Native AWS/EFS namespace in CloudWatch | File-system throughput, I/O mix, storage bytes, client connections, headroom, replication lag | Best service-level baseline and always-on for core metrics | Does not expose application latency or server-side error counts [S1][S2] |
| CloudWatch storage-class dimensions | StorageBytes dimensions on AWS/EFS metrics | Standard, IA, Archive, and overhead storage mix | Best cost and lifecycle posture signal | Exporter may normalize storage-class dimension names unexpectedly [S2] |
| Performance/throughput configuration docs | AWS EFS config and performance metadata | Explains whether credits matter and whether `PercentIOLimit` is relevant | Essential for interpreting metrics correctly | These are inventory facts, not always emitted as metric labels [S3][S4] |
| Replication metrics | CloudWatch plus replication configuration | `TimeSinceLastSync` per source/destination pair | Clear DR freshness signal | Metric absent when replication is not configured [S2][S6] |
| Mount helper support logs | `amazon-efs-utils` logs on clients | TLS, watchdog, mount helper failures | Best source for client mount failures | Lives on clients, not the EFS service; requires log collection [S8][S9] |
| Mount attempt CloudWatch Logs | Optional `amazon-efs-utils` CloudWatch logging | Remote success/failure of mount attempts and mount status events | Good Stage 4 route candidate | Must be explicitly enabled in `efs-utils.conf` [S7] |

### Best-practice inference
- In this workspace, `TimeSinceLastSync` is absent entirely, so replication freshness remains gated rather than shown as healthy-zero.
- "No data" on `BurstCreditBalance` can be legitimate if the file system uses Elastic or Provisioned throughput rather than Bursting.
- "No data" on storage-class splits may mean the exporter kept only the total storage series or the file system has not tiered data yet.

## Log intelligence (Stage 4 handoff)

### Confirmed by sources
1. **Log sources matrix**

| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|---|---|---|---|---|
| Mount helper support logs | `/var/log/amazon/efs` on client hosts | Plain-text helper, watchdog, and optional stunnel logs | Unstructured/semi-structured | [S8] |
| Mount attempt CloudWatch Logs | Configured in `efs-utils.conf`, default pattern `/aws/efs/utils/{fs_id}` when customized | Line-oriented mount success/failure events | Semi-structured | [S7] |
| EFS mount helper runtime | `mount.efs` via `amazon-efs-utils` | Client-side command and TLS/watchdog behavior | Unstructured | [S8][S9] |

2. **Known log formats**
- **Mount helper support log**: line-oriented text in `/var/log/amazon/efs`; includes mount helper, watchdog, and optional stunnel log content. Good for TLS bootstrap, watchdog restart, and mount negotiation failures. [S8]
- **Mount attempt CloudWatch log**: success/failure notification stream created when CloudWatch logging is enabled in `efs-utils.conf`; useful for remote mount-attempt auditing without logging into instances. [S7]

3. **Candidate query filters for Stage 4**
- Precise: `context.log_group:/aws/efs/utils/ AND context.filesystemid:*`
  Rationale: targets opt-in mount-attempt log groups after normalization.
  Risk: requires CloudWatch logging to be enabled and the log-group field to be preserved.
- Fallback: `(message:*amazon-efs-mount-watchdog* OR message:*mount.efs* OR message:*efs-utils*) AND context.team:*`
  Rationale: catches client-side EFS helper logs even if log-group metadata is inconsistent.
  Risk: may mix helper logs from multiple hosts and file systems.

4. **Attribute mapping hints**

| Raw field | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| file system id (`fs-...`) | `context.filesystemid` | High | Best join key between logs and metrics |
| destination file system id | `context.destinationfilesystemid` | Medium | Useful only if replication tooling logs it |
| mount target or DNS name | `context.mount_target` | Medium | Good for network-path failures |
| client hostname | `context.host.name` | Medium | Useful in logs, avoid in metric widgets |
| availability zone | `context.cloud.availability_zone` | Medium | Useful for One Zone mount troubleshooting |
| helper component (`mount helper`, `watchdog`, `stunnel`) | `context.component` | High | Supports split parsers and log filtering |
| mount status | `context.mount.status` | High | Useful derived status field for mount-attempt logs |
| error reason | `context.error.reason` | Medium | Best free-text classification target |

5. **Parsing risks**
- Support logs are client-side and line-oriented; they are not guaranteed to include a stable JSON structure.
- Optional stunnel logging is disabled by default, so TLS details may be absent even when mounts fail. [S8]
- CloudWatch mount-attempt logs are opt-in and may not exist in the workspace at all. [S7]
- Filesystem id may appear in different forms across mount paths, helper arguments, or log group names.
- Multi-host aggregation can create noisy mixed streams unless file-system id and host identity are extracted.

### Best-practice inference
- Stage 4 should prefer parsing helper and watchdog component names plus filesystem id first; these are lower-cardinality and more reusable than raw mount commands.
- If no EFS-specific logs are present in Tsuga, a route may still be useful for generic NFS mount-failure logs from EC2 or Kubernetes node agents.

## Caveats and footguns
- **[fleet-health]** `PercentIOLimit` applies to the General Purpose performance mode; treat absence or low relevance carefully on Max I/O or unsupported surfaces. (S3)
- **[fleet-health]** `BurstCreditBalance` is meaningful only for Bursting throughput; Elastic throughput does not accrue or consume credits. (S3)
- **[fleet-health]** `PermittedThroughput` can exceed provisioned throughput when Standard storage size would allow more; do not assume it equals a configured provisioned number. (S2)(S3)
- **[fleet-health, throughput-mix]** Reads are discounted in EFS throughput accounting, so `MeteredIOBytes` and `TotalIOBytes` diverging is normal for read-heavy workloads. (S2)(S3)
- **[throughput-mix]** `MetadataIOBytes` can rise sharply during namespace scans, deploys that touch many files, or small-file storms; this does not necessarily mean user data throughput increased. (Inference)
- **[throughput-mix]** `SampleCount` on EFS byte metrics represents operation count, not bytes. If Tsuga preserves it, divide by seconds for ops/s rather than treating it as throughput. (S2)
- **[fleet-health]** `ClientConnections` only supports the `Sum` statistic in CloudWatch; averages across long windows need period-aware interpretation. (S2)
- **[fleet-health]** One standard client usually means one connection per mounted EC2 instance; high client count can reflect fanout, not necessarily unhealthy load. (S2)
- **[storage-lifecycle]** `StorageBytes` is emitted every 15 minutes, not every minute like most EFS metrics. Short time windows can make storage widgets look stale. (S2)
- **[storage-lifecycle]** IA and Archive metered size include 128 KiB minimum billing effects on small files; overhead growth can be a billing artifact, not actual data expansion. (S2)(S4)
- **[storage-lifecycle]** Archive is supported only with Elastic throughput; if Archive data exists, do not assume throughput mode can be switched freely. (S4)
- **[storage-lifecycle]** Cold-storage tiers have tens-of-milliseconds first-byte latency; rising IA or Archive share is not automatically bad, but it changes user latency expectations. (S3)(S4)
- **[replication-resilience]** `TimeSinceLastSync` measures elapsed time since the last successful sync, not a point-in-time-consistent replication lag guarantee. (S6)
- **[replication-resilience]** AWS states a 15-minute RPO for most file systems after initial sync, but very large or frequently changing file systems can exceed that. (S6)
- **[replication-resilience]** Absence of replication metrics usually means replication is not configured, not that lag is zero. (S2)(S6)
- **[fleet-health, replication-resilience]** One Zone file systems are not resilient to loss of the AZ; treat DR freshness and backup posture more seriously there. (S4)
- **[throughput-mix]** EFS does not expose per-directory, per-path, or per-user service metrics, so hot-subtree diagnosis requires client or application telemetry. (Inference)
- **[throughput-mix, fleet-health]** Application-visible slowness may come from NFS semantics, client-side caching, or mount/network issues that are invisible in EFS service metrics. (S5)(S8)(S9)
- **[replication-resilience]** Initial sync time depends on file count and file size; newly enabled replication can look unhealthy for a while without indicating ongoing replication failure. (S6)
- **[fleet-health]** Max I/O has inherently higher per-operation latency than General Purpose; do not compare those modes as if they share the same normal latency baseline. (S3)
- **[storage-lifecycle]** Standard storage growth can increase bursting baseline throughput, so rising storage is not always purely a cost negative. (S3)
- **[throughput-mix]** Read-heavy workloads can look healthier in metered throughput than in actual throughput because reads count at one-third rate. (S2)(S3)

## Confirmed Tsuga prefixes
- `aws_efs_*` — **CONFIRMED** (10 metrics found in Tsuga via `tsuga_search_metrics.py '^aws_efs.*'` and validated with MCP `get_metric`)
- `aws.efs.*` — **UNKNOWN / RULED OUT** (no dot-normalized EFS family found in Tsuga)

## Discovery status
- Discovery complete in Stage 2: 10 metrics confirmed, 3 expected AWS-documented metrics missing (`DataReadIOBytes`, `DataWriteIOBytes`, `TimeSinceLastSync`), 0 unexpected metrics found.

## Top sources
- [S1] https://docs.aws.amazon.com/efs/latest/ug/monitoring-cloudwatch.html - Canonical entry point for EFS CloudWatch monitoring behavior and 1-minute metric cadence.
- [S2] https://docs.aws.amazon.com/efs/latest/ug/efs-metrics.html - Primary source for exact EFS metric names, dimensions, statistics, storage-class splits, and replication metric semantics.
- [S3] https://docs.aws.amazon.com/efs/latest/ug/performance.html - Explains throughput modes, performance modes, burst credits, and why `PercentIOLimit` and `PermittedThroughput` matter.
- [S4] https://docs.aws.amazon.com/efs/latest/ug/features.html - Defines Regional vs One Zone durability and storage-class behavior that shape dashboard interpretation.
- [S5] https://docs.aws.amazon.com/efs/latest/ug/efs-mount-helper.html - Grounds the client-side mount helper as a key operational surface for non-service-side failures.
- [S6] https://docs.aws.amazon.com/efs/latest/ug/efs-replication.html - Primary source for replication behavior, RPO language, and `TimeSinceLastSync` usage.
- [S7] https://docs.aws.amazon.com/efs/latest/ug/how-to-monitor-mount-status.html - Best source for mount-attempt CloudWatch Logs and opt-in log-group behavior.
- [S8] https://docs.aws.amazon.com/efs/latest/ug/mount-helper-logs.html - Primary source for support log location, helper/watchdog logging, and log retention caveats.
- [S9] https://docs.aws.amazon.com/efs/latest/ug/lifecycle-management-efs.html - Lifecycle policy source for Standard, IA, and Archive movement and cost-oriented storage posture.
- [S10] https://aws.amazon.com/efs/pricing/ - Pricing source for why `StorageBytes` and throughput/operation volume are the practical cost proxies.
