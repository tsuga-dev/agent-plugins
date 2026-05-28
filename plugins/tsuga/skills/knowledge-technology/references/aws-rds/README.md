# AWS RDS Integration Context Bundle

## Metadata
**Technology:** AWS RDS
**Deployment:** managed
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** mixed
**Integration scope:** core service only
**Primary use-case:** reliability and performance

## How to use this bundle
- Use `01_aws-rds_metrics.csv` as the source of truth for metric names, units, temporality assumptions, and safe query patterns.
- Use `02_aws-rds_dashboard_plan.yaml` as the implementation blueprint for sections, widgets, derived signals, explanation notes, triage chains, and playbooks.
- Use `03_aws-rds_state.yaml` as the machine-readable state file for stage status, inferred namespace mappings, log intelligence status, and unresolved unknowns.
- Use `04_aws-rds_memory.md` for the human-readable Stage 1 handoff narrative and Stage 2 priority checks.
- Stage 2 will create `05_aws-rds_metric_catalog.csv` as the discovered inventory and reconciliation memory for actual Tsuga metric and attribute coverage.
- Stage 4 should read `00` under `Log intelligence (Stage 4 handoff)` and `03.log_intel` before attempting log route creation.

## What it is and what "good" looks like

### Confirmed by sources
- Amazon RDS is a managed relational database service that surfaces operational health primarily through CloudWatch metrics, optional Enhanced Monitoring OS telemetry, Performance Insights DB load metrics, events, and engine log exports. [S1][S3][S4][S5][S8]
- CloudWatch instance metrics are the universal baseline for fleet health: `CPUUtilization`, `DatabaseConnections`, `FreeableMemory`, `FreeStorageSpace`, IOPS, latency, throughput, and engine-specific replication or log-space metrics. [S1]
- Enhanced Monitoring adds instance OS signals such as `cpuUtilization`, `diskIO`, `loadAverageMinute`, `memory`, `swap`, and `tasks`, which matter when CloudWatch shows pressure but not the operating-system reason. [S4]
- Performance Insights adds database load split into `DBLoad`, `DBLoadCPU`, `DBLoadNonCPU`, and `DBLoadRelativeToNumVCPUs`, which are the closest thing RDS has to a direct saturation signal inside the database engine. [S3][S7]
- "Good" for RDS is stable client connectivity, low and explainable DB load, storage headroom, read/write latency that matches traffic shape, and replication staying close enough to real time for the workload. [S1][S3][S4]
- Dashboard paging intent should quickly separate four distinct shapes: instance resource exhaustion, storage exhaustion, engine-internal contention, and replication drift.

### Best-practice inference
- Incident shape 1: **Fleet health regression**. Start in `fleet-health` to determine if the issue is broad (CPU, memory, connection count) or isolated to one instance class/engine/region.
- Incident shape 2: **Traffic or latency regression**. Start in `traffic-connections` and `latency-io` to see whether demand, I/O pressure, or network saturation changed first.
- Incident shape 3: **Storage or engine pressure**. Start in `storage-capacity` and `engine-pressure` when write-heavy workloads, transaction logs, or wait-heavy DB load are suspected.
- Incident shape 4: **Replica drift or failover risk**. Start in `replication-resilience`; replication-specific metrics are often the earliest sign of read-replica or engine-specific durability pain.
- A useful dashboard for RDS must support both umbrella coverage across engines and explicit gating for engine-specific metrics, because MySQL, PostgreSQL, SQL Server, Oracle, and MariaDB do not expose the same secondary signals. [S1][S5][S6]

## Key concepts

### Glossary

| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| DB instance | The managed RDS compute and storage endpoint for one database deployment | Primary blast-radius boundary for dashboards and filters | fleet-health |
| Read replica | A replica instance asynchronously following a writer | Lag here is early warning for stale reads and failover risk | replication-resilience |
| Multi-AZ | RDS high-availability deployment using standby infrastructure | Helps interpret whether replication/failover signals are expected | replication-resilience |
| CloudWatch metric | Native AWS service metric emitted for an RDS instance or related surface | Universal baseline telemetry across all engines | all |
| Enhanced Monitoring | OS-level telemetry stream emitted from the RDS host | Explains host pressure that CloudWatch alone cannot | fleet-health |
| Performance Insights | Database load and wait analysis subsystem | Best source for engine saturation and CPU vs wait split | engine-pressure |
| DB load | Average active sessions running or waiting for resources | Most direct "is the engine overloaded?" signal | engine-pressure |
| vCPU saturation | DB load relative to available vCPUs | Distinguishes healthy parallelism from overloaded CPU demand | engine-pressure |
| Database connections | Number of client database connections | First demand and pool-pressure signal | traffic-connections |
| Freeable memory | Reclaimable memory reported by CloudWatch | Low headroom here often precedes latency and swap pressure | fleet-health |
| Free storage space | Remaining allocatable storage | The main "time to outage" storage headroom signal | storage-capacity |
| Disk queue depth | Number of queued disk operations | Rising queue depth with latency means storage pressure | latency-io |
| Read IOPS | Read operations per second | Characterizes read demand and storage stress | latency-io |
| Write IOPS | Write operations per second | Characterizes write demand and commit pressure | latency-io |
| Read latency | Average latency per read I/O operation | Indicates storage responsiveness for read paths | latency-io |
| Write latency | Average latency per write I/O operation | Indicates storage responsiveness for writes and commits | latency-io |
| Throughput | Bytes transferred per second for reads, writes, or network | Separates bandwidth-bound incidents from IOPS-bound incidents | latency-io |
| Burst balance | Remaining burst credits for burstable storage | Falling credits mean future performance cliffs, not just current pain | storage-capacity |
| Deadlock | Transaction deadlock count | Symptom of application contention or lock design problems | engine-pressure |
| Replica lag | Delay between writer and replica application | Measures replica freshness and resilience risk | replication-resilience |
| Transaction log disk usage | Storage consumed by transaction logs | Critical for SQL Server or heavy write workloads | storage-capacity |
| Binlog disk usage | Disk consumed by MySQL binary logs | Indicates replication/log-retention pressure | replication-resilience |
| Replication slot disk usage | Disk consumed by PostgreSQL logical replication slots | Can silently consume storage if consumers stall | replication-resilience |
| Oldest replication slot lag | Logical slot lag in PostgreSQL | Strong early warning for stalled CDC consumers | replication-resilience |
| Network receive/transmit throughput | Network ingress and egress at the instance | Helps distinguish client surges from storage or engine stalls | traffic-connections |
| Engine-specific metric | Metric emitted only for a particular engine family or feature | Must be gated in dashboards to avoid false "no data" alarms | all |

[S1][S3][S4][S5][S6][S7]

### Concept Map
Client application -> opens -> Database connection (why: demand starts as connection pressure before query saturation)
Connection pool -> fans into -> DB instance (why: pool spikes can inflate `DatabaseConnections` without proportional CPU)
DB instance -> emits -> CloudWatch metrics (why: baseline availability and resource posture)
DB instance -> can emit -> Enhanced Monitoring OS metrics (why: host-level saturation details)
DB instance -> can emit -> Performance Insights DB load (why: engine contention and wait visibility)
DB instance -> stores on -> EBS-backed storage volume (why: read/write latency and queue depth reflect storage health)
Storage volume -> constrains -> ReadLatency and WriteLatency (why: queueing or credit loss shows up as slower I/O)
ReadIOPS/WriteIOPS -> drive -> ReadThroughput/WriteThroughput (why: operation count and bandwidth should be interpreted together)
FreeStorageSpace -> limits -> transaction growth runway (why: low headroom turns routine write spikes into outages)
BurstBalance -> buffers -> temporary burst demand (why: depletion predicts future performance cliffs)
Database workload -> increases -> DBLoad (why: active sessions rise when more work or more waits exist)
DBLoadCPU -> represents -> runnable on-CPU load (why: compute saturation)
DBLoadNonCPU -> represents -> waiting load (why: lock, I/O, or other resource contention)
DBLoadRelativeToNumVCPUs -> compares -> DBLoad against CPU capacity (why: quick saturation thresholding)
Application query pattern -> can create -> Deadlocks (why: lock ordering or long transactions collide)
Writer instance -> replicates to -> Read replica (why: freshness and HA depend on timely replication)
ReplicaLag -> measures -> replication drift (why: stale reads and slow failover risk)
MySQL binary log retention -> consumes -> BinLogDiskUsage (why: backlog or retention settings can fill storage)
PostgreSQL logical slots -> consume -> ReplicationSlotDiskUsage (why: stalled consumers pin WAL files)
OldestReplicationSlotLag -> indicates -> CDC consumer delay (why: replication slots can fall behind before disks fill)
SQL Server transaction logs -> consume -> TransactionLogsDiskUsage (why: long transactions or backup gaps exhaust storage)
CloudWatch dimensions -> map to -> instance, engine, class, region, volume (why: safe operational group-by axes)
context.env/context.team -> scope -> ownership and environment boundaries (why: dashboard filters must reflect org routing)
context.dbinstanceidentifier -> anchors -> per-instance attribution (why: first-line isolation axis)
context.enginename -> explains -> metric availability differences (why: engine-specific widgets must be gated)
context.cloud.region -> localizes -> regional incidents and replication topology (why: regional AWS issues are a real failure domain)
Engine logs -> complement -> metric-only triage (why: deadlocks, slow queries, auth failures, and replication warnings often appear in logs first)

### Entities and dimensions

| Entity/Dimension | Why useful | Cardinality risk | Safe top-N | Do NOT group-by guidance |
|---|---|---|---|---|
| `context.env` | Environment boundary for prod vs non-prod | Low | 5 | Keep as a global filter, not a timeseries split in every chart |
| `context.team` | Ownership routing and escalation | Low | 10 | Avoid using it as the first technical diagnostic axis |
| `context.dbinstanceidentifier` | Primary per-instance attribution | Confirmed | 20 | Safe first-line filter and the main instance-level grouping key discovered in Tsuga |
| `context.databaseclass` | Capacity-envelope comparison across instance sizes | Confirmed | 12 | Use sparingly beside instance filters to avoid redundant splits |
| `context.enginename` | Explains which metrics should exist | Confirmed | 8 | Safe engine-level gating field for section notes and optional splits |
| `context.cloud.region` | Regional failure-domain isolation | Low | 10 | Prefer region over AZ unless you know AZ labels exist consistently |
| `context.storage.volume.name` | Needed for EBS balance metrics when emitted per volume | Medium | 8 | Do not use unless Stage 2 confirms the field exists |
| `context.aws.account.id` | Multi-account segmentation | Medium | 10 | Skip if the org runs a single account; adds clutter fast |
| `context.role` | Writer vs reader role split | Confirmed on replica metrics | 4 | Use only where the live metric actually carries the field |
| `context.databaseinsightsmode` | Performance Insights export mode hint | Confirmed on PI-derived metrics | 6 | This is not a wait-category breakdown and should not be treated as one |
| `context.pi.sql_digest` | SQL-level attribution for DB load | High | 10 | Do not place on overview dashboards; cardinality risk is high |
| `context.db.name` | Useful for multi-database instances | Medium | 12 | Avoid unless metrics are actually tagged at DB granularity |
| `context.db.user` | Helpful for connection or auth spikes | Medium-High | 10 | Do not use by default in metric widgets |
| `context.log.type` | Differentiates error/slowquery/general/postgresql logs | Low | 8 | Log-only field; do not assume it exists on metrics |

### Tsuga field mapping

| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| `DBInstanceIdentifier` | `context.dbinstanceidentifier` | Confirmed in Stage 2 |
| `DatabaseClass` | `context.databaseclass` | Confirmed in Stage 2 |
| `EngineName` | `context.enginename` | Confirmed in Stage 2 |
| `SourceRegion` | `context.cloud.region` | Optional |
| `VolumeBytesUsed` or volume dimension for EBS balance metrics | `context.storage.volume.name` | Optional |
| Read replica role | `context.role` | Confirmed on replica-oriented metrics |
| Performance Insights mode hint | `context.databaseinsightsmode` | Confirmed on at least one PI-derived metric |
| Performance Insights SQL digest / statement group | `context.pi.sql_digest` | Optional |
| Environment tag from org enrichment | `context.env` | Must-exist |
| Team tag from org enrichment | `context.team` | Must-exist |
| AWS account id from enrichment | `context.aws.account.id` | Optional |
| CloudWatch log type (error/general/slowquery/postgresql) | `context.log.type` | Optional |

### Confirmed by sources
- Amazon RDS CloudWatch metrics use dimensions such as `DBInstanceIdentifier`, `DatabaseClass`, `EngineName`, and for some EBS balance metrics `SourceRegion` or `VolumeBytesUsed`. [S2]
- MySQL, PostgreSQL, and other engines export different log types, so log routing and metric gating must acknowledge engine differences. [S5][S6][S8]

### Best-practice inference
- Stage 2 discovery confirmed flattened `context.*` keys rather than nested `context.db.*` segments for the core metric filters.
- No wait-category dimension was confirmed during Stage 2 discovery; `context.databaseinsightsmode` appeared, but it is a mode/export hint rather than a wait breakdown.

## Golden signals

### Confirmed by sources
| Signal | What it means for AWS RDS | Typical degradation causes | Best telemetry sources | What people page on | Section questions |
|---|---|---|---|---|---|
| Traffic | Connection demand plus network ingress/egress into the DB | Client surge, pool leak, reconnect storm, workload shift | `DatabaseConnections`, `NetworkReceiveThroughput`, `NetworkTransmitThroughput` [S1] | Connection count jumping while work or latency worsens | Is traffic normal? Is demand broad or isolated? |
| Errors | Lock-contention and engine-failure symptoms rather than HTTP-style errors | Deadlocks, auth failures, transaction/log pressure, engine restarts | `Deadlocks`, engine logs, events [S1][S8] | Deadlocks rising or logs showing repeated failures | Is this an application contention issue or engine distress? |
| Latency | Storage and engine response slowness | I/O queueing, credit depletion, memory pressure, waits | `ReadLatency`, `WriteLatency`, `DiskQueueDepth`, PI load metrics [S1][S3][S4] | Latency rising with queue depth or wait-heavy DB load | Is slowness coming from storage, CPU, or waits? |
| Saturation | Headroom exhaustion in CPU, memory, storage, credits, or replicas | CPU exhaustion, low freeable memory, low storage, low burst credits, replica backlog | `CPUUtilization`, `FreeableMemory`, `FreeStorageSpace`, `BurstBalance`, `DBLoadRelativeToNumVCPUs`, `ReplicaLag` [S1][S3][S4] | Headroom collapsing toward outage or failover risk | Which capacity limit is closest to failing? |

### Best-practice inference
- For RDS, `DBLoad` and `DBLoadRelativeToNumVCPUs` are more actionable for saturation triage than CPU alone because they distinguish CPU work from wait-bound overload.
- `ReplicaLag`, `OldestReplicationSlotLag`, `ReplicationSlotDiskUsage`, and the promoted `ChangeLogBytesUsed` signal are higher-value resilience indicators than raw network counters when the incident is replica freshness or CDC drift.

## Telemetry sources

### Confirmed by sources
| Source type | How collected | What it provides | Pros/cons | Common pitfalls |
|---|---|---|---|---|
| CloudWatch instance metrics | Native RDS -> CloudWatch | Core resource, network, I/O, connection, and engine-specific health metrics | Always available baseline; low friction; cross-engine | Some metrics are engine- or storage-type specific, so "no data" may mean unsupported rather than healthy zero [S1] |
| CloudWatch dimensions | Metric metadata from AWS dimensions | Instance, class, engine, region, and sometimes volume attribution | Enables safe global filters and group-bys | Do not assume every metric carries every dimension [S2] |
| Performance Insights metrics | PI -> CloudWatch integration | `DBLoad`, `DBLoadCPU`, `DBLoadNonCPU`, and relative load metrics | Best engine saturation surface | Requires PI enabled; coverage changes as PI support evolves [S3][S7] |
| Enhanced Monitoring | Agent-like OS telemetry on the RDS host | `cpuUtilization`, `diskIO`, `loadAverageMinute`, `memory`, `swap`, `tasks` | Best explanation layer for host/resource incidents | Must be explicitly enabled; OS units differ from CloudWatch instance metrics [S4] |
| RDS logs exported to CloudWatch Logs | Engine logs and audit/slow/error streams | Deadlocks, slow queries, auth failures, replication warnings | Best for root cause after metrics point to a problem | Export types differ per engine and often require parameter changes [S5][S6][S8] |
| RDS events | Service/control-plane events | Failovers, maintenance, configuration changes | Good incident context | Not a substitute for continuous performance metrics [S8] |

### Best-practice inference
- "No data" usually means one of three things: the metric is engine-specific, the feature is disabled (Performance Insights, Enhanced Monitoring, log export), or the chosen namespace mapping in Tsuga is wrong.
- Stage 2 should verify whether Tsuga exports only CloudWatch-style metrics or also PI/Enhanced Monitoring-derived namespaces before overcommitting widgets to those surfaces.

## Log intelligence (Stage 4 handoff)

### Confirmed by sources
1. **Log sources matrix**

| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|---|---|---|---|---|
| MySQL error log | CloudWatch Logs group `/aws/rds/instance/<db>/error` | Plain-text engine error lines | Unstructured/semi-structured | [S5][S8] |
| MySQL slow query log | CloudWatch Logs group `/aws/rds/instance/<db>/slowquery` | MySQL slow-log text records | Semi-structured multiline | [S5] |
| MySQL general log | CloudWatch Logs group `/aws/rds/instance/<db>/general` | General query/event text lines | Semi-structured | [S5] |
| MySQL audit log | CloudWatch Logs group `/aws/rds/instance/<db>/audit` | Audit records from `MARIADB_AUDIT_PLUGIN` | Structured-ish text | [S5] |
| PostgreSQL log | RDS PostgreSQL log files and optional CloudWatch export | `stderr`-style PostgreSQL log lines or CSV-style when configured | Semi-structured or structured depending on configuration | [S6][S8] |

2. **Known log formats**
- **MySQL slow query log**: multiline record with timestamp/user/host/query-time/lock-time/rows and SQL text body. Delimiters are label-based, not JSON; SQL body can span lines. [S5]
- **MySQL error/general log**: line-oriented text; timestamps are engine-generated and may include thread/session details. [S5]
- **PostgreSQL log (`stderr`)**: text line with timestamp, optional PID/session fields, severity, and message; exact prefix depends on `log_line_prefix`. [S6]
- **PostgreSQL CSV log**: comma-separated fields when `csvlog` is enabled; safer for parsing but not guaranteed on every RDS instance. [S6]

3. **Candidate query filters for Stage 4**
- Precise: `source:rds AND context.dbinstanceidentifier:* AND (context.log.type:error OR context.log.type:slowquery OR context.log.type:postgresql)`
  Rationale: targets exported RDS engine logs if ingestion normalized log types.
  Risk: `context.log.type` may not exist yet.
- Fallback: `source:rds AND context.dbinstanceidentifier:*`
  Rationale: broad enough to catch all exported RDS logs after instance enrichment.
  Risk: may mix multiple engines and log types into one stream.

4. **Attribute mapping hints**

| Raw field | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| DB instance identifier | `context.dbinstanceidentifier` | High | Confirmed on live metrics and the best candidate for multi-instance routing |
| Engine name | `context.enginename` | Medium | Confirmed on live metrics and useful for engine-specific parsing branches |
| Log type (`error`,`general`,`slowquery`,`postgresql`) | `context.log.type` | Medium | Best routing split if available |
| User | `context.db.user` | Medium | Present in slow/general/audit or PostgreSQL prefix depending on config |
| Database name | `context.db.name` | Medium | Often present in PostgreSQL or slow query contexts |
| Process / thread id | `context.process.pid` | Medium | Useful for correlating repeated failure lines |
| Query duration | `context.db.query.duration_ms` | Medium | Slow query and statement-duration parsing target |
| SQL text / statement | `context.db.statement` | Low | High-cardinality, likely keep as raw body not routing field |

5. **Parsing risks**
- MySQL slow query logs are multiline and include SQL payloads, so naïve line parsers will fragment one event into many.
- PostgreSQL prefix format varies with `log_line_prefix`; a route must not assume one exact prefix unless the environment confirms it.
- PostgreSQL can emit either text or CSV-style logs depending on configuration; dual-format handling may be required. [S6]
- Engine log types are optional exports; absence may mean disabled export rather than no problems.
- CloudWatch log group naming is stable, but downstream ingestion fields (`source`, `service`, `context.log.type`) are not yet confirmed in Tsuga.

### Best-practice inference
- Stage 4 should branch parser selection first by engine (`context.enginename`) and then by log type because MySQL/PostgreSQL formats differ materially.
- Start with line-oriented parsing for error/general logs and a dedicated multiline strategy for MySQL slow-query logs.
- If PostgreSQL CSV logging is enabled, prefer CSV parsing over grok because field boundaries are more reliable.

## Caveats and footguns
- **[fleet-health]** `CPUUtilization` can stay moderate while `DBLoadNonCPU` climbs, so CPU alone does not clear the database of saturation. (S1, S3)
- **[fleet-health]** `FreeableMemory` is reclaimable memory, not "unused" memory; low values are actionable, high cache use alone is not. (S1)
- **[fleet-health]** Enhanced Monitoring `memory` values are in kilobytes and should not be mixed directly with CloudWatch byte metrics without normalization. (S4)
- **[fleet-health]** Enhanced Monitoring must be enabled; missing host metrics usually means the feature is off. (S4)
- **[traffic-connections]** `DatabaseConnections` can rise from connection storms or pool leaks even when throughput is flat. (Inference)
- **[traffic-connections]** Network throughput is supportive context, not a direct success metric; low network with high load can still mean lock contention. (Inference)
- **[traffic-connections]** Grouping by raw client/session identifiers would explode cardinality; prefer instance, engine, class, and region. (Inference)
- **[latency-io]** `ReadLatency` and `WriteLatency` are averages; they are not percentiles and can hide tail pain. (S1)
- **[latency-io]** `DiskQueueDepth` rising with flat IOPS often means storage cannot keep up, not that the app is idle. (S1)
- **[latency-io]** Read/write throughput without IOPS can be misleading because large sequential operations and small random operations behave very differently. (Inference)
- **[latency-io]** `EBSByteBalance%` and `EBSIOBalance%` are storage-type dependent and not emitted for every deployment. (S1)
- **[storage-capacity]** `BurstBalance` is forward-looking; trouble starts when credits keep draining under steady demand, not only when it hits zero. (S1)
- **[storage-capacity]** `FreeStorageSpace` can collapse from transaction-log retention or stalled replication, not only from user tables growing. (S1, S6)
- **[storage-capacity]** `TransactionLogsDiskUsage` is SQL Server-specific and should be gated. (S1)
- **[storage-capacity]** `ReplicationSlotDiskUsage` and `OldestReplicationSlotLag` are PostgreSQL-specific and absent on other engines. (S1)
- **[storage-capacity]** `BinLogDiskUsage` is MySQL/MariaDB specific and was not present in the live Stage 2 Tsuga catalog for this workspace; keep it gated and do not treat missing data as healthy zero for PostgreSQL or SQL Server. (S1 + Stage 2 discovery)
- **[engine-pressure]** `DBLoad`, `DBLoadCPU`, and `DBLoadNonCPU` depend on Performance Insights; widgets must explain missing-feature behavior. (S3, S7)
- **[engine-pressure]** `DBLoadCPU + DBLoadNonCPU` is a useful split, but the sum may not match every downstream export perfectly if Tsuga exports a transformed PI surface. (Inference)
- **[engine-pressure]** `DBLoadRelativeToNumVCPUs` is already a ratio; do not apply rate or treat it as a counter. (S3)
- **[engine-pressure]** `Deadlocks` is an engine symptom, not an availability metric; a small but sudden increase can still matter. (S1)
- **[replication-resilience]** `ReplicaLag` should be treated as optional for non-replica deployments; missing lag does not automatically mean healthy replication. (S1)
- **[replication-resilience]** Replication metrics are strongly engine- and topology-dependent; do not assume a writer-only instance should emit them. (S1)
- **[replication-resilience]** PostgreSQL slot lag metrics point to CDC/logical consumers, not ordinary read replicas. (S1)
- **[replication-resilience]** Log-space metrics and lag metrics together are more meaningful than either alone; slot lag without disk growth can be transient, disk growth without lag can be retention policy. (Inference)
- **[fleet-health, engine-pressure]** Mixing CloudWatch, Enhanced Monitoring, and Performance Insights into one formula widget can create unit confusion unless the derived signal has one clear purpose. (Inference)

## Confirmed Tsuga prefixes
- `aws_rds_` — **CONFIRMED** (Stage 2 live discovery returned 60 metrics with underscore-separated names such as `aws_rds_cpu_utilization` and `aws_rds_db_load`).
- `aws_rds` — **CONFIRMED ROOT** (the namespace root is valid, but the live catalog uses snake_case names rather than dot-separated metric segments).

## Discovery status
Discovery: completed in Stage 2.
- Authentication succeeded after the user refreshed `.env`, and Tsuga catalog discovery returned 60 live `aws_rds_*` metrics.
- The live catalog uses underscore-separated names, so Stage 1 placeholder references like `aws_rds.CPUUtilization` were reconciled to names such as `aws_rds_cpu_utilization`.
- Representative live metrics expose usable attribute keys including `context.dbinstanceidentifier`, `context.enginename`, `context.databaseclass`, `context.cloud.region`, `context.dbclusteridentifier`, and `context.role`.
- All spot-checked live metrics currently report as `type: summary` with `temporality: cumulative`, so rate/counter assumptions were removed from the plan where they were unsafe.
- `BinLogDiskUsage` remains documented by AWS but was not found in the live Tsuga catalog for this workspace; the bundle keeps it gated and uses `ChangeLogBytesUsed` as the promoted storage-pressure companion signal where applicable.
- Scalar freshness spot-checks against the aggregation API returned `500 INTERNAL_ERROR`, so presence and schema are confirmed, but point-value validation is still inconclusive.

## Top sources
1. https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-metrics.html
   Why: canonical CloudWatch metric catalog for RDS, including core and engine-specific metrics.
2. https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/dimensions.html
   Why: authoritative CloudWatch dimension list for RDS metrics and safe grouping assumptions.
3. https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.Cloudwatch.html
   Why: defines Performance Insights CloudWatch metrics such as `DBLoad` and CPU/non-CPU splits.
4. https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_Monitoring-Available-OS-Metrics.html
   Why: Enhanced Monitoring OS metric catalog and units.
5. https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Monitor_Logs_Events.html
   Why: RDS logs/events overview and where logs fit in operational monitoring.
6. https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_LogAccess.html
   Why: general RDS log-file access model and export context.
7. https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_LogAccess.MySQLDB.PublishtoCloudWatchLogs.html
   Why: exact MySQL CloudWatch log-group naming and export prerequisites.
8. https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_LogAccess.Concepts.PostgreSQL.html
   Why: PostgreSQL log concepts, log types, and export behavior.
9. https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_LogAccess.Concepts.PostgreSQL.Query_Logging.html
   Why: PostgreSQL query logging details relevant to Stage 4 route design.
10. https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.Overview.html
   Why: performance-insight semantics and feature context for DB load interpretation.

---

**Citation key**
- [S1] https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-metrics.html
- [S2] https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/dimensions.html
- [S3] https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.Cloudwatch.html
- [S4] https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_Monitoring-Available-OS-Metrics.html
- [S5] https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_LogAccess.MySQLDB.PublishtoCloudWatchLogs.html
- [S6] https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_LogAccess.Concepts.PostgreSQL.html
- [S7] https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.Overview.html
- [S8] https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Monitor_Logs_Events.html
