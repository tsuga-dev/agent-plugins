# AWS DocDB Integration Context Bundle

## Metadata
**Technology:** AWS DocDB
**Deployment:** managed
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** mixed
**Integration scope:** core service only
**Primary use-case:** reliability and performance

## How to use this bundle
- Use `01_aws-docdb_metrics.csv` as the source of truth for DocDB metric names, units, and safe widget/query patterns.
- Use `02_aws-docdb_dashboard_plan.yaml` for the proposed overview and deep-dive sections, derived signals, notes, and playbooks.
- Use `03_aws-docdb_state.yaml` for machine-readable stage state, assumptions, namespace hints, and unresolved unknowns.
- Use `04_aws-docdb_memory.md` for the human-readable Stage 1 handoff and Stage 2 verification priorities.
- Stage 2 will add `05_aws-docdb_metric_catalog.csv` as the discovered Tsuga inventory and reconciliation record.
- Stage 4 should read this file's `Log intelligence (Stage 4 handoff)` section and `03.log_intel` before authoring any log routes.

## What it is and what "good" looks like

### Confirmed by sources
- Amazon DocumentDB is a managed, MongoDB-compatible document database whose baseline health is expressed through CloudWatch instance and cluster metrics, with deeper engine load exposed through Performance Insights when enabled. [S1][S2][S3]
- The core operational surfaces are instance resource pressure, query and document operation volume, cache effectiveness, replica lag, and storage-side pressure. [S1][S2]
- "Good" for DocDB means writer and readers are reachable, client connections stay below instance limits, replica lag remains low, cache hit ratios stay high enough that volume I/O does not become the bottleneck, and low-memory throttling stays at zero. [S1][S2]
- Change streams, profiler logs, and audit logs are optional but operationally important. They add context for write amplification, slow operations, and access/security investigations. [S5][S6][S7]
- Paging intent should first separate: writer or cluster distress, memory/cache collapse, storage latency, and replication/change-stream backlog.

### Best-practice inference
- Incident shape 1: **Cluster health regression**. Start in `cluster-health` to decide whether the problem is broad, reader-only, or isolated to one instance.
- Incident shape 2: **Throughput or query-path regression**. Start in `traffic-operations` to determine whether command/query load, returned document volume, or connection concurrency changed first.
- Incident shape 3: **Latency driven by cache or storage**. Start in `latency-storage` and `cache-memory`; cache misses and billed volume I/O matter more than raw CPU for DocDB read-path triage.
- Incident shape 4: **Replication or change-stream risk**. Start in `replication-change-streams`; replica lag and change-stream log growth are the fastest signals of data freshness or cost risk.
- A useful dashboard must be explicit about feature-gated surfaces: Performance Insights, audit logs, profiler logs, NVMe-backed metrics, and T3 CPU credit metrics are not universal. [S1][S3][S5][S6]

## Key concepts

### Glossary

| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| Cluster | The Amazon DocumentDB deployment boundary containing one writer and zero or more readers | Main blast radius for storage, change streams, and aggregate replication state | cluster-health |
| Writer | Primary instance accepting writes | First place to check for write-path saturation and memory pressure | cluster-health |
| Reader | Replica instance serving read traffic and replication apply | Reader lag or poor cache state often causes stale or slow reads | replication-change-streams |
| DBClusterIdentifier | CloudWatch cluster dimension | Best cluster-wide filter when storage or replica metrics are used | all |
| DBInstanceIdentifier | CloudWatch instance dimension | Main per-instance drilldown key | all |
| Role | CloudWatch cluster role dimension (`WRITER` or `READER`) | Safest split for top-level writer vs reader comparisons | cluster-health |
| DatabaseConnections | Number of client-initiated connections on an instance | Early signal for pool leaks, reconnect storms, or hot instances | cluster-health |
| DatabaseConnectionsLimit | Max allowed concurrent connections on an instance | Required denominator for safe connection-utilization reasoning | cluster-health |
| DatabaseCursors | Number of open cursors | Useful for cursor leaks and fan-out query patterns | traffic-operations |
| Opcounters | Per-minute counts of MongoDB-compatible operation classes | Fastest way to separate read-heavy, write-heavy, and command-heavy demand | traffic-operations |
| DocumentsReturned | Returned document count over the minute | Useful to detect fan-out or unbounded queries | traffic-operations |
| BufferCacheHitRatio | Percent of requests served from buffer cache | Most important read-path efficiency signal after basic health | cache-memory |
| IndexBufferCacheHitRatio | Percent of index requests served from cache | Falling values often precede billed read I/O growth | cache-memory |
| LowMemThrottleQueueDepth | Queue depth of requests throttled for low memory | Clear memory distress signal with direct user impact | cache-memory |
| LowMemNumOperationsThrottled | Count of operations throttled because memory is low | Best "this is hurting users now" memory symptom | cache-memory |
| FreeableMemory | Available RAM in bytes | Headroom indicator; low values plus cache misses usually mean pressure | cache-memory |
| FreeLocalStorage | Temporary local storage available for logs and temp tables | Important for spill-heavy work and local temp exhaustion | cache-memory |
| SwapUsage | Swap in use on the instance | Non-zero or growing swap is a late memory distress signal | cache-memory |
| ReadLatency | Average time per disk read I/O | One of the clearest storage stress indicators | latency-storage |
| WriteLatency | Average time per disk write I/O | Important for write stalls and storage saturation | latency-storage |
| VolumeReadIOPs | Billed read I/O operations at cluster volume level | Better cost and miss-path signal than instance `ReadIOPS` alone | latency-storage |
| VolumeWriteIOPs | Billed write I/O operations at cluster volume level | Indicates storage-layer cost and replication/write amplification | latency-storage |
| DBClusterReplicaLagMaximum | Max lag between writer and replicas | Top cluster-level freshness risk signal | replication-change-streams |
| DBInstanceReplicaLag | Lag for a specific replica instance | Best drilldown signal for one bad reader | replication-change-streams |
| ChangeStreamLogSize | Storage consumed by retained change stream log | Direct cost and backlog indicator for CDC-driven use cases | replication-change-streams |
| AvailableMVCCIds | Remaining write IDs before the cluster becomes read-only | Rare but critical exhaustion signal on write-heavy or GC-impaired clusters | capacity-cost |
| TransactionsOpen | Current open transactions | Useful for long-running transactions and lock/memory amplification | traffic-operations |
| TransactionsAborted | Aborted transactions in the minute | Strong symptom of application retries or contention | traffic-operations |
| NVMeStorageCacheHitRatio | Cache hit ratio for tiered cache on NVMe-backed instances | Optional high-value signal for NVMe-capable families | latency-storage |
| CPUCreditBalance | Remaining burst credits on T3 instances | Needed only for burstable classes; absent elsewhere | capacity-cost |

[S1][S2][S3][S7]

### Concept Map
Client application -> opens -> Database connection (why: demand first appears as connection concurrency)
Connection pool -> concentrates on -> Writer or reader instance (why: one hot app tier can overload one instance before the cluster)
Writer -> replicates to -> Reader instances (why: freshness and read scaling depend on replica apply health)
Cluster -> exposes -> Cluster-level lag metrics (why: replica health is not visible from one instance alone)
Instance -> emits -> CPU, memory, cursor, and operation metrics (why: instance distress is often the first operational boundary)
Query workload -> drives -> Opcounters and DocumentsReturned (why: traffic shape matters more than request count alone)
DocumentsReturned -> amplifies -> Storage reads (why: fan-out queries pull more pages and can inflate billed reads)
Buffer cache -> reduces -> VolumeReadIOPs (why: cache hits avoid storage access)
Index cache -> protects -> Query latency (why: missed index pages force expensive storage fetches)
FreeableMemory -> constrains -> Cache residency (why: shrinking memory usually means poorer cache hit ratios)
Low memory -> triggers -> Operation throttling (why: DocDB explicitly queues and throttles work under low memory)
Low memory throttling -> increases -> Client-visible latency (why: requests wait before execution)
FreeLocalStorage -> supports -> Temporary tables and logs (why: some operations need local scratch space)
Swap usage -> follows -> Severe memory pressure (why: swap is a late, expensive fallback)
ReadLatency -> reflects -> Storage read path health (why: misses and storage pressure show up here)
WriteLatency -> reflects -> Storage write path health (why: commits and replication materialization depend on writes)
VolumeReadIOPs -> depends on -> Cache miss behavior (why: billed reads occur when data is not in buffer cache)
VolumeWriteIOPs -> depends on -> Write volume plus replication/storage behavior (why: write amplification affects cost and latency)
Change streams -> consume -> ChangeStreamLogSize (why: longer retention or slow consumers retain more log)
ChangeStreamLogSize -> increases -> Storage cost and pressure (why: it is a subset of cluster storage)
TransactionsOpen -> increases -> Memory and lock footprint (why: long-running transactions hold resources)
TransactionsAborted -> signals -> contention or application retries (why: not all failed work appears as simple error counts)
Performance Insights -> emits -> DBLoad and wait split (why: engine saturation is more meaningful than CPU alone)
DBLoadNonCPU -> usually indicates -> waits on memory, locks, or storage (why: CPU is not the only bottleneck)
Audit logs -> capture -> auth, DDL, DML, and authorization events (why: security and access investigations need logs)
Profiler logs -> capture -> slow operations and plan summaries (why: metrics tell you something is wrong; profiler shows which operations)
context.env/context.team -> scope -> ownership and environment routing (why: dashboards must support operational boundaries)
context.dbclusteridentifier/context.dbinstanceidentifier -> anchor -> bounded group-by strategy (why: these are safe, useful drilldown keys)

### Entities and dimensions

| Entity/Dimension | Why useful | Cardinality risk | Safe top-N | Do NOT group-by guidance |
|---|---|---|---|---|
| `context.env` | Fast prod/non-prod split | Low | 5 | Use as global filter rather than on every chart |
| `context.team` | Ownership boundary | Low | 10 | Avoid using it as the first technical split |
| `context.dbclusteridentifier` | Best cluster-wide filter and top-list key | Low | 10 | Prefer this over account-wide or tenant-like keys |
| `context.dbinstanceidentifier` | Main per-instance attribution | Low | 20 | Safe default instance group-by |
| `context.role` | Writer vs reader separation | Low | 4 | Avoid stacking with too many other dimensions |
| `context.cloud.region` | Regional failure-domain split | Low | 10 | Prefer region over AZ unless AZ is confirmed in Tsuga |
| `context.cloud.account.id` | Multi-account scoping | Medium | 10 | Skip if the workspace is single-account |
| `context.collection` | Useful for hot collection investigation | High | 10 | Keep out of overview widgets unless Stage 2 proves bounded coverage |
| `context.database` | Helpful if multiple logical databases are tagged | Medium | 12 | Do not assume it exists on all metrics |
| `context.operation` | Useful for command or workload class analysis | Medium | 10 | Avoid if values are sparse or unnormalized |
| `context.change_stream` | Useful for CDC troubleshooting | Medium | 8 | Only use if Stage 2 confirms a bounded field |
| `context.instance.class` | Explains different limits and temp storage behavior | Medium | 10 | Do not mix with instance id in every widget |
| `context.engine.version` | Important for feature availability | Medium | 8 | Use for notes/gating, not routine timeseries splits |

### Tsuga field mapping

| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| `DBClusterIdentifier` | `context.dbclusteridentifier` | Must-exist |
| `DBInstanceIdentifier` | `context.dbinstanceidentifier` | Must-exist |
| `Role` | `context.role` | Must-exist on cluster-role surfaces |
| AWS region enrichment | `context.cloud.region` | Optional |
| AWS account enrichment | `context.cloud.account.id` | Confirmed in Stage 2 |
| Environment tag enrichment | `context.env` | Must-exist |
| Team tag enrichment | `context.team` | Must-exist |
| Collection name from profiler/audit enrichment | `context.collection` | Optional |
| Logical database name from profiler/audit enrichment | `context.database` | Optional |
| Operation name from profiler/audit enrichment | `context.operation` | Optional |

### Confirmed by sources
- CloudWatch exposes `DBClusterIdentifier`, `DBClusterIdentifier, Role`, and `DBInstanceIdentifier` dimensions for DocumentDB metrics. [S1]
- Audit logs are JSON documents exported to CloudWatch Logs; profiler logs include command, plan summary, timestamp, and client metadata. [S5][S6]

### Best-practice inference
- Stage 2 should prefer flattened `context.dbclusteridentifier`, `context.dbinstanceidentifier`, and `context.role` keys over deeply nested or source-specific aliases.
- Collection-, database-, and operation-level keys should be treated as log/profiler-only until discovered in Tsuga metrics.

## Golden signals

### Confirmed by sources
| Signal | What it means for AWS DocDB | Typical degradation causes | Best telemetry sources | What people page on | Section questions |
|---|---|---|---|---|---|
| Traffic | Whether clients are connecting and issuing healthy read/write/command volume | Reconnect storms, hot reader, unbounded queries, retry loops | `DatabaseConnections`, `Opcounters*`, `DocumentsReturned`, network throughput [S1] | Connections surge, ops skew sharply, or document-return volume spikes unexpectedly | Is demand normal? Is load read-heavy, write-heavy, or pathological? |
| Errors | Not classic HTTP errors, but aborted work, timeouts, throttling, and auth failures | Low memory throttling, aborted transactions, auth failures, audit events | `LowMemNumOperationsThrottled`, `TransactionsAborted`, audit logs [S1][S6] | Throttled or aborted work rising, failed authentication activity, or repeated denied operations | Is user work failing now, and is the cause memory, auth, or contention? |
| Latency | How expensive it is to serve storage-backed or wait-heavy work | Cache miss storm, storage pressure, replica lag, slow operations | `ReadLatency`, `WriteLatency`, `VolumeReadIOPs`, profiler logs, PI load [S1][S3][S5] | Read/write latency increases with cache drop or storage I/O growth | Is the slowness in storage, memory/cache, or engine waits? |
| Saturation | Whether memory, cache, storage, or replication headroom is running out | Low free memory, swap use, low local storage, change-stream growth, MVCC pressure | `FreeableMemory`, `FreeLocalStorage`, `SwapUsage`, `LowMemThrottleQueueDepth`, `ChangeStreamLogSize`, `AvailableMVCCIds`, replica lag [S1][S7] | Memory throttling, shrinking storage headroom, lag growth, or MVCC runway collapse | Which resource is closest to failing first? |

### Best-practice inference
- For DocDB, cache effectiveness and low-memory throttling are more actionable than CPU alone because poor cache residency converts ordinary read traffic into storage latency and cost.
- Replica lag and change-stream log growth matter more than generic throughput when the workload depends on readers, CDC pipelines, or near-real-time projections.

## Telemetry sources

### Confirmed by sources
| Source type | How collected | What it provides | Pros/cons | Common pitfalls |
|---|---|---|---|---|
| CloudWatch DocDB metrics | Native service metrics in namespace `AWS/DocDB` | Core instance, cluster, operation, latency, throughput, cache, and cost-adjacent signals | Always the baseline; broad coverage | Some metrics are cluster-level, some instance-level, and some are optional by instance family [S1] |
| Performance Insights CloudWatch metrics | PI-published `DBLoad*` metrics | Engine load and CPU vs non-CPU wait split | Best saturation signal when enabled | Published only when PI is enabled and there is load on the instance [S3] |
| CloudWatch audit logs | Optional audit export | Auth, DDL, DML, authorization, and user-management events | Best for access/security and correctness context | Disabled by default; DML payload fields are truncated at 1 KB [S6] |
| CloudWatch profiler logs | Optional profiler export | Slow operation details, command, plan summary, time, client metadata | Best for slow-query style investigation | Disabled by default and adds resource overhead; threshold selection matters [S5] |
| Change streams | App-level CDC feature plus change-stream retention metric | CDC semantics and backlog/cost context | Important when downstream consumers exist | Not every deployment uses change streams; backlog may look like storage growth if unlabeled [S1][S7] |
| Event subscriptions | Control-plane notifications | Maintenance, failover, and cluster event context | Good incident timeline context | Not a replacement for continuous metrics and not always ingested into Tsuga [S8] |

### Best-practice inference
- "No data" on audit or profiler widgets usually means the feature is disabled, not that no risky events exist.
- "No data" on NVMe or T3 metrics usually means the instance family does not support that surface.
- Stage 2 confirmed the live export is `aws_docdb_*` and does not currently include replica-lag or Performance Insights `DBLoad*` metrics in this workspace, so those surfaces must stay gated.

## Log intelligence (Stage 4 handoff)

### Confirmed by sources
1. **Log sources matrix**

| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|---|---|---|---|---|
| Audit log | CloudWatch Logs export from the cluster | JSON documents | Structured | [S6] |
| Profiler log | CloudWatch Logs export from the cluster | JSON-like operation records with command metadata | Structured/semi-structured | [S5] |
| Control-plane event notifications | SNS/Event Subscription destinations | Event payloads, not engine logs | Structured | [S8] |

2. **Known log formats**
- **Audit events**: JSON documents containing event category, event type, auth/authorization results, and DML or DDL context. DML `param` values are truncated at 1 KB. [S6]
- **Profiler records**: operation-oriented records containing execution time, profiled command, timestamp, plan summary, and client metadata. Exported only when the profiler is enabled and the threshold is met. [S5]

3. **Candidate query filters for Stage 4**
- Precise: `source:docdb AND (context.log.type:audit OR context.log.type:profiler) AND context.dbclusteridentifier:*`
  Rationale: directly targets the two known log surfaces.
  Risk: `context.log.type` may not exist yet.
- Fallback: `source:docdb AND context.dbclusteridentifier:*`
  Rationale: safer if only the cluster identifier is normalized.
  Risk: may mix audit and profiler events into one stream.

4. **Attribute mapping hints**

| Raw field | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| Cluster identifier | `context.dbclusteridentifier` | High | Strongest routing key for DocDB logs |
| Instance identifier | `context.dbinstanceidentifier` | Medium | Helpful when profiler records carry instance context |
| Event type | `context.operation` | Medium | Good fit for audit event names like `authenticate`, `find`, `update` |
| Database name | `context.database` | Medium | Likely present on many audit/profiler events |
| Collection name | `context.collection` | Medium | High value for hot collection triage |
| Auth result / error code | `context.result.code` | Medium | Useful for auth failure investigations |
| Client metadata | `context.client` | Low | Valuable but may be high-cardinality |

5. **Parsing risks**
- Audit and profiler surfaces are optional and disabled by default, so empty result sets may reflect config rather than health. [S5][S6]
- Audit JSON truncates large DML parameter values after 1 KB, so parsers must not assume full payload fidelity. [S6]
- Profiler thresholds materially change event volume and semantics; one cluster may log only very slow operations while another logs more aggressively. [S5]
- Event-subscription notifications are not a substitute for query or engine logs and should not be mixed into the same parsing route.

### Best-practice inference
- Stage 4 should build separate parsing paths for audit vs profiler streams if log type can be detected.
- `context.operation`, `context.database`, and `context.collection` are the highest-value target fields for investigative search, but they should be added only if sample events confirm stable shapes.

## Caveats and footguns
- **[cluster-health]** `DatabaseConnections` counts client-initiated connections only; engine/internal health checks can make engine-level commands show slightly more. [S1]
- **[cluster-health]** `DatabaseConnectionsMax` is a per-minute maximum, not an always-current gauge. [S1]
- **[cluster-health]** `DatabaseConnectionsLimit` varies by instance class, so absolute counts without the limit can mislead. (Inference)
- **[traffic-operations]** Idle clusters still show non-zero opcounter values because DocumentDB performs periodic health checks and internal work. [S1]
- **[traffic-operations]** `DocumentsReturned` can explode for one bad query pattern even when query counts stay flat. (Inference)
- **[traffic-operations]** Cursor counts are useful, but grouping by raw client metadata would be too high-cardinality for a default dashboard. (Inference)
- **[traffic-operations]** `TransactionsOpen` without `TransactionsOpenLimit` context can cause false concern on large instances. (Inference)
- **[traffic-operations]** `TransactionsAborted` is a symptom, not a root cause; pair it with profiler or audit context. (Inference)
- **[latency-storage]** `VolumeReadIOPs` and `VolumeWriteIOPs` are storage-layer metrics reported at 5-minute intervals and can repeat the same datapoint across the period. [S1]
- **[latency-storage]** Volume I/O is aggregated at cluster storage level and should not be treated as a per-instance real-time throughput metric. [S1]
- **[latency-storage]** `ReadLatency` and `WriteLatency` are averages, not percentiles. [S1]
- **[latency-storage]** NVMe metrics exist only on NVMe-backed instance families; absence is not equivalent to healthy zero. [S1]
- **[cache-memory, latency-storage]** A drop in `IndexBufferCacheHitRatio` can transiently exceed 100 percent right after dropping an index, collection, or database. [S1]
- **[cache-memory]** `FreeLocalStorage` is temporary scratch and log space, not the cluster volume. [S1]
- **[cache-memory]** `SwapUsage` is already a late-stage signal; waiting for swap before paging is too late. (Inference)
- **[cache-memory]** `LowMemThrottleQueueDepth` and `LowMemNumOperationsThrottled` are higher-signal user-impact metrics than CPU during memory crises. (Inference)
- **[cache-memory]** Cache-hit ratios are percentages and should not be re-normalized with rate functions. [S1]
- **[replication-change-streams]** `DBClusterReplicaLagMaximum` can hide one unhealthy reader behind a fleet view; pair with `DBInstanceReplicaLag` for drilldown. [S1]
- **[replication-change-streams]** `ChangeStreamLogSize` is a subset of `VolumeBytesUsed`; do not sum them and call it total storage. [S1][S7]
- **[replication-change-streams]** No change-stream consumer metric is guaranteed in CloudWatch, so backlog cause often has to be inferred from app context or logs. (Inference)
- **[capacity-cost]** `AvailableMVCCIds` is rare but critical: when it reaches zero, the cluster becomes read-only until IDs are reclaimed. [S1]
- **[capacity-cost]** T3 CPU credit metrics apply only to T3-backed instances; keep those widgets gated. [S1]
- **[capacity-cost]** Backup- and snapshot-storage metrics are cost surfaces, not immediate availability surfaces. [S1]

## Confirmed Tsuga prefixes
- `aws_docdb_` - **CONFIRMED** (65 live metrics present in Tsuga over the last 24 hours; this is the real namespace family used in this workspace).
- `aws_docdb.*` - **INFERRED** (useful as a human alias, but Tsuga normalizes the live family to `aws_docdb_` rather than dot notation).

## Discovery status
- Discovery completed in Stage 2 and was rerun after the Tsuga MCP update; direct MCP catalog listing and the repo discovery scripts both confirmed the same 65 live `aws_docdb_*` metrics.
- Live Tsuga discovery found **65** `aws_docdb_*` metrics.
- Reconciliation outcome: **58 confirmed** in `01`, **6 missing** from the Stage 1 seed, and **7 live-only metrics** kept in `05` without promotion to `01`.
- Key naming corrections: cluster volume metrics live as `aws_docdb_volume_read_io_ps` and `aws_docdb_volume_write_io_ps`, not the Stage 1 `..._iops` placeholders.
- Key field corrections: the live account field is `context.cloud.account.id`; `context.dbclusteridentifier`, `context.dbinstanceidentifier`, `context.role`, `context.cloud.region`, `context.env`, `context.team`, and `context.source` are the reusable discovery anchors.
- Missing documented surfaces in this workspace: replica-lag metrics, `DBLoad*` Performance Insights metrics, and NVMe cache-hit metrics.
- Spot-check data validation by scalar aggregation was **inconclusive** because Tsuga returned `500 INTERNAL_ERROR` even for confirmed live metrics, so Stage 2 relied on catalog and metadata evidence rather than zero-count assumptions.

## Top sources
1. https://docs.aws.amazon.com/documentdb/latest/developerguide/cloud_watch.html - Authoritative CloudWatch metric, dimension, and unit reference for DocumentDB.
2. https://docs.aws.amazon.com/documentdb/latest/developerguide/performance-insights.html - Best source for why DB load matters and when PI should influence dashboard design.
3. https://docs.aws.amazon.com/documentdb/latest/developerguide/performance-insights-cloudwatch.html - Exact PI CloudWatch metrics (`DBLoad`, `DBLoadCPU`, `DBLoadNonCPU`) and publication behavior.
4. https://docs.aws.amazon.com/documentdb/latest/developerguide/performance-insights-metrics.html - PI API semantics and decomposition dimensions useful for later enrichment decisions.
5. https://docs.aws.amazon.com/documentdb/latest/developerguide/profiling.html - Profiler log shape, enablement model, and operational tradeoffs.
6. https://docs.aws.amazon.com/documentdb/latest/developerguide/event-auditing.html - Audit event categories, JSON log export behavior, and truncation caveats.
7. https://docs.aws.amazon.com/documentdb/latest/developerguide/change_streams.html - Change-stream semantics and retention behavior behind `ChangeStreamLogSize`.
8. https://docs.aws.amazon.com/documentdb/latest/developerguide/event-subscriptions.subscribe.html - Event-subscription model for control-plane context and operational timeline enrichment.
9. https://docs.aws.amazon.com/documentdb/latest/developerguide/best_practices.html - General DocumentDB operational guidance useful for section ordering and footguns.
10. https://aws.amazon.com/documentdb/pricing/ - Pricing context for why `VolumeBytesUsed`, backup storage, and change-stream retention deserve cost-aware coverage.

## Source Legend
- `[S1]` CloudWatch metrics and dimensions
- `[S2]` Performance Insights overview
- `[S3]` Performance Insights CloudWatch metrics
- `[S4]` Performance Insights API metrics
- `[S5]` Profiler logs
- `[S6]` Audit logs
- `[S7]` Change streams
- `[S8]` Event subscriptions
- `[S9]` Best practices
- `[S10]` Pricing
