# AWS DynamoDB Integration Context Bundle

## Metadata
**Technology:** AWS DynamoDB
**Deployment:** managed
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** mixed
**Integration scope:** core service only
**Primary use-case:** reliability and performance

## How to use this bundle
- Use `01_aws-dynamodb_metrics.csv` as the source of truth for DynamoDB metric names, units, and safe aggregation patterns.
- Use `02_aws-dynamodb_dashboard_plan.yaml` for the dashboard structure, derived signals, explanation notes, and playbooks.
- Use `03_aws-dynamodb_state.yaml` for machine-readable assumptions, prefix status, log intelligence status, and unresolved unknowns.
- Use `04_aws-dynamodb_memory.md` for the concise Stage 1 handoff and Stage 2 verification order.
- Stage 2 will create `05_aws-dynamodb_metric_catalog.csv` as the discovered Tsuga metric inventory and reconciliation memory.
- Stage 4 should read this file's `Log intelligence (Stage 4 handoff)` section and `03.log_intel` before proposing any log routes.

## What it is and what "good" looks like

### Confirmed by sources
- Amazon DynamoDB is a fully managed key-value and document database where operational health is mainly a function of request latency, throughput consumption, throttling, and replication state for global tables or Kinesis-backed change data capture. [S1][S4][S5]
- DynamoDB exposes service metrics through CloudWatch for tables, global secondary indexes, operations, account-level limits, online index builds, and global-table replication. [S1][S4]
- "Good" for DynamoDB means request latency is stable, consumed capacity remains comfortably below the active provisioned or on-demand ceiling, throttling is rare, and any replication backlog remains low and short-lived. [S1][S2][S4]
- CloudWatch Contributor Insights is the fastest built-in path for finding hot keys and throttled keys when the aggregate metrics say there is a hotspot but do not identify the key. [S2][S3]
- CloudTrail provides API-level history for table mutations, scaling changes, IAM access patterns, and data-plane events if enabled, but it is not a substitute for steady-state service metrics. [S6]

### Best-practice inference
- Incident shape 1: **Latency or customer-visible slowness**. Start in `request-health` to decide whether latency moved first or whether throttling and capacity pressure explain it.
- Incident shape 2: **Capacity or throttle regression**. Start in `capacity-mode` and `throttling-hotspots` to separate provisioned exhaustion, on-demand ceilings, account quotas, and hot partitions.
- Incident shape 3: **Global table or CDC lag**. Start in `replication-cdc`; replication latency and oldest unreplicated age matter more than generic request throughput when cross-Region freshness is the concern.
- Incident shape 4: **Index build or schema change side effects**. Start in `index-operations`; online index progress and index-build throttle counters tell you whether a planned change is the reason baseline traffic is degrading.
- Paging intent should prioritize user-visible request failure or sustained throttling over raw consumption percentages. DynamoDB can run hot without user pain, but repeated throttle events, growing replication age, or an index build colliding with production traffic are direct operational risks.

## Key concepts

### Glossary

| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| Table | Primary DynamoDB storage object | Main unit for traffic, latency, and throttle attribution | request-health |
| Global secondary index (GSI) | Alternate query surface with separate capacity behavior | A table can look healthy while one GSI is the actual bottleneck | index-operations |
| Partition key | Primary key component used for data placement | Hot keys create partition-level throttling before total table capacity is exhausted | throttling-hotspots |
| Sort key | Optional second key component used for ordered access | Drives item-shape and query behavior, but is usually too high-cardinality for default metric group-bys | request-health |
| Provisioned mode | Capacity mode with explicit RCU/WCU allocation | Requires utilization and scaling-headroom tracking | capacity-mode |
| On-demand mode | Capacity mode that auto-scales request units | Still subject to per-table, per-index, and account ceilings | capacity-mode |
| Consumed read capacity units | Read throughput actually used over the period | Best baseline for read demand and one denominator for read saturation | capacity-mode |
| Consumed write capacity units | Write throughput actually used over the period | Best baseline for write demand and one denominator for write saturation | capacity-mode |
| Throttled request | Request rejected because throughput or quota limits were exceeded | User-visible symptom that matters more than raw capacity percentage | throttling-hotspots |
| Read throttle events | Read-side throttled events at table or GSI scope | Separates read pain from write pain | throttling-hotspots |
| Write throttle events | Write-side throttled events at table or GSI scope | Useful when write amplification or index fan-out is the issue | throttling-hotspots |
| Key range throughput exceeded | Partition-level limit breach | Strong sign of hot partition or poor key distribution | throttling-hotspots |
| Account limit exceeded | Regional account quota breach | Means local tuning will not fully help until quotas or traffic shape change | capacity-mode |
| Successful request latency | Latency for successful operations | Best user-facing performance surface when segmented by operation | request-health |
| User errors | HTTP 400-class request issues | Often client misuse, bad requests, or transaction conflicts rather than service failure | latency-errors |
| System errors | HTTP 500-class service-side failures | Rare and high signal when non-zero | latency-errors |
| Conditional check failure | Write rejected because a condition expression evaluated false | Usually expected contention or optimistic locking behavior, not a platform outage | latency-errors |
| Transaction conflict | Rejected item-level transactional request due to concurrency conflict | Critical for transactional workloads that appear slow despite low throttle counts | latency-errors |
| Returned bytes | Response payload bytes returned | Useful to separate "slow because large result sets" from "slow because throttled" | request-health |
| Returned item count | Items returned by reads | High values often indicate inefficient query or scan patterns | request-health |
| Replication latency | Cross-Region lag for global tables | Direct freshness risk for failover and multi-Region reads | replication-cdc |
| Pending replication count | Updates not yet applied to another replica | Backlog indicator for global table propagation | replication-cdc |
| Age of oldest unreplicated record | Time since the oldest not-yet-replicated record arrived | Better urgency signal than backlog size alone | replication-cdc |
| Consumed change data capture units | Change-data-capture work consumed for Kinesis integration | Helps quantify CDC cost or downstream pressure | replication-cdc |
| Online index percentage progress | Progress of a new GSI build | Explains planned operational noise during schema evolution | index-operations |
| Contributor Insights | CloudWatch top-N analysis for accessed or throttled keys | Best way to pivot from aggregate throttle metrics to hot-key evidence | throttling-hotspots |

### Concept Map
Client request -> targets -> DynamoDB table (why: every incident starts at table or index scope)
Table request -> may route through -> Global secondary index (why: a GSI can throttle independently of the base table)
Provisioned table -> bounded by -> ProvisionedReadCapacityUnits and ProvisionedWriteCapacityUnits (why: utilization above this drives provisioned throttling)
On-demand table -> bounded by -> OnDemandMaxReadRequestUnits and OnDemandMaxWriteRequestUnits (why: user-configured or service limits can still cap burst traffic)
Request mix -> drives -> ConsumedReadCapacityUnits and ConsumedWriteCapacityUnits (why: these are the cleanest demand baselines)
High consumed capacity -> does not always imply -> user pain (why: adaptive capacity and burst behavior can absorb short spikes)
Hot partition key -> causes -> ReadKeyRangeThroughputThrottleEvents or WriteKeyRangeThroughputThrottleEvents (why: partition limits trip before table totals)
Hot partition -> identified by -> Contributor Insights throttled keys reports (why: aggregate table metrics hide which keys are hottest)
ThrottledRequests -> summarizes -> request-level impact (why: it answers whether callers were rejected at all)
ReadThrottleEvents and WriteThrottleEvents -> explain -> event-level scope of rejection (why: one request can create multiple throttled events)
SuccessfulRequestLatency -> shaped by -> operation type and payload size (why: Query and Scan behavior can differ sharply from point reads)
ReturnedItemCount -> amplifies -> ReturnedBytes (why: larger result sets often explain rising successful latency)
Conditional writes -> increment -> ConditionalCheckFailedRequests (why: contention can look like errors without being platform failure)
Concurrent transactions -> increment -> TransactionConflict (why: item-level contention is a workload-shape issue, not usually a service outage)
SystemErrors -> indicate -> DynamoDB-side failure (why: they are rarer and higher-severity than client-side errors)
Global table replica -> receives -> replicated writes from source Region (why: freshness depends on cross-Region apply)
PendingReplicationCount -> raises -> ReplicationLatency and AgeOfOldestUnreplicatedRecord risk (why: backlog that lasts long enough becomes stale data)
Kinesis CDC integration -> consumes -> ConsumedChangeDataCaptureUnits (why: downstream change-stream usage adds cost and replication-style pressure)
FailedToReplicateRecordCount -> signals -> dropped or stuck CDC delivery (why: this is stronger than a backlog warning)
Online GSI build -> consumes -> OnlineIndexConsumedWriteCapacity (why: schema changes compete with steady-state traffic)
Online index build -> exposes -> OnlineIndexPercentageProgress (why: operators need to distinguish planned backfill from unexplained saturation)
context.env and context.team -> scope -> ownership and paging boundaries (why: dashboards must support service ownership, not only raw AWS dimensions)
context.tablename and context.globalsecondaryindexname -> anchor -> safe default group-bys (why: table and GSI are useful and bounded)
CloudTrail data events -> capture -> API caller and request context (why: they help explain who changed or accessed what when metrics show a symptom)

### Entities and dimensions

| Entity/Dimension | Why useful | Cardinality risk | Safe top-N suggestion | Do NOT group-by guidance |
|---|---|---|---|---|
| `context.env` | Separates prod from lower-risk environments | Low | 5 | Prefer as a global filter, not repeated series on every chart |
| `context.team` | Ownership and escalation boundary | Low | 10 | Use as filter first, not as the primary technical split |
| `context.cloud.region` | Failure domain and replica boundary | Low | 10 | Use Region before Availability Zone unless AZ is actually present |
| `context.cloud.account.id` | Multi-account scope control | Medium | 10 | Skip if the workspace is single-account |
| `context.tablename` | Primary table attribution | Low to medium | 20 | Safe default table split for most charts |
| `context.globalsecondaryindexname` | Reveals index-specific hotspots | Medium | 20 | Do not combine with high-cardinality request parameters |
| `context.operation` | Helps split `Query`, `Scan`, `GetItem`, `PutItem`, and transactional operations | Medium | 12 | Confirm existence in Stage 2 before making it a dashboard-wide filter |
| `context.receivingregion` | Needed for global-table backlog analysis | Low | 10 | Use only in replication sections |
| `context.delegatedoperation` | Required for CDC metrics to distinguish Kinesis replication work | Medium | 10 | Keep to CDC sections only |
| `context.billingmode` | Distinguishes on-demand from provisioned behavior | Low | 4 | Treat as optional enrichment, not guaranteed metric metadata |
| `context.source` | Helpful to distinguish cloudwatch vs enriched pipelines | Low | 4 | Not useful as an end-user default filter |
| `context.aws.resource.arn` | Useful for drilldown or links, especially for GSI and table resources | Medium | 10 | Avoid chart legends based on full ARN strings |
| `context.partitionkey` | Useful only when Contributor Insights or logs expose it | Very high | 25 max when explicitly investigating | Never use as a default group-by in service dashboards |

### Tsuga field mapping

| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| `TableName` | `context.tablename` | Must-exist |
| `GlobalSecondaryIndexName` | `context.globalsecondaryindexname` | Optional but strongly preferred |
| `Operation` | `context.operation` | Optional |
| `ReceivingRegion` | `context.receivingregion` | Optional |
| `DelegatedOperation` | `context.delegatedoperation` | Optional |
| AWS Region enrichment | `context.cloud.region` | Must-exist |
| AWS account enrichment | `context.cloud.account.id` | Optional |
| Environment tag enrichment | `context.env` | Must-exist |
| Team tag enrichment | `context.team` | Must-exist |
| Contributor Insights hot key payload | `context.partitionkey` | Optional and high-risk |
| Billing mode metadata | `context.billingmode` | Optional |
| Resource ARN enrichment | `context.aws.resource.arn` | Optional |

### Confirmed by sources
- The CloudWatch metrics reference explicitly documents `TableName`, `GlobalSecondaryIndexName`, `Operation`, `ReceivingRegion`, and `DelegatedOperation` as DynamoDB metric dimensions depending on metric family. [S1]
- CloudTrail events for DynamoDB include API action, actor, time, source IP, and request details, which makes them the most realistic Stage 4 log source for service-generated operational history. [S6]

### Best-practice inference
- Stage 2 should prefer flattened keys such as `context.tablename`, `context.globalsecondaryindexname`, `context.operation`, and `context.receivingregion` if multiple source-specific aliases exist.
- Partition-key level fields should remain investigation-only fields. They are valuable when present, but they are too sensitive and high-cardinality for default dashboard filters.

## Golden signals

### Confirmed by sources
| Signal | What it means for AWS DynamoDB | Typical degradation causes | Best telemetry sources | What people page on | Section questions |
|---|---|---|---|---|---|
| Traffic | Read and write request volume, result-set size, and capacity consumption shape | Bursty clients, index backfill overlap, scans, retry storms | `ConsumedReadCapacityUnits`, `ConsumedWriteCapacityUnits`, `ReturnedBytes`, `ReturnedItemCount` [S1] | Consumption climbs sharply or result sizes balloon before latency degrades | Is demand higher, or is the workload simply less efficient? |
| Errors | Client-side misuse, concurrency conflicts, and service-side failures | Bad request patterns, conditional contention, transactional conflicts, rare platform errors | `UserErrors`, `ConditionalCheckFailedRequests`, `TransactionConflict`, `SystemErrors` [S1][S8] | System errors or transaction conflicts rise enough to affect successful work | Are failures due to callers, concurrency, or the service itself? |
| Latency | Time to complete successful requests | Large result sets, scans, retries, throttle retries, hot partitions, cross-Region lag | `SuccessfulRequestLatency`, `ReturnedBytes`, `ReturnedItemCount`, replication metrics [S1][S4] | Sustained latency increase, especially when throttling or payload growth also rises | Is slowness request-shape-driven, throttle-driven, or replica-driven? |
| Saturation | Nearness to throughput ceilings, quotas, and hotspot boundaries | Provisioned under-sizing, on-demand max limits, account quotas, hot partitions, GSI backfill | Consumed vs provisioned or on-demand limit metrics, throttle metrics, Contributor Insights [S1][S2][S3] | Repeated throttle events, partition-level throttle indicators, quota-limit throttle counts | Which limit is actually binding: table, index, partition, on-demand max, or account quota? |

### Best-practice inference
- For DynamoDB, throttle classification matters more than CPU-style host metrics because the service hides host internals and instead exposes the limit surface directly. A good dashboard should answer "what kind of throttle is this?" before it asks "how busy is the service?"
- Returned bytes and returned item count matter more than a generic request-count graph because many DynamoDB latency incidents are query-shape or scan-shape problems rather than pure request volume problems.
- Replication backlog should be treated like a fifth golden signal when global tables or Kinesis CDC are in use because stale data is an application-level outage even if the base table is still serving requests.

## Telemetry sources

### Confirmed by sources
| Source type | How collected | What it provides | Pros/cons | Common pitfalls |
|---|---|---|---|---|
| CloudWatch DynamoDB metrics | Native service metrics in the DynamoDB namespace | Throughput, throttling, errors, latency, global-table, CDC, and index-build signals | Broadest coverage and best default source | Many metrics are scoped differently by table, GSI, operation, or receiving Region [S1] |
| CloudWatch Contributor Insights | Enabled per table or GSI | Top accessed and throttled keys | Best hotspot evidence without custom logs | Not enabled everywhere; key data can be sensitive; max 25 contributors in reports [S3] |
| CloudTrail management events | Enabled by default in account history, or via trails | Table creation, scaling changes, policy changes, stream settings, GSI changes | Best control-plane change history | Event history is short unless trails are retained centrally [S6] |
| CloudTrail data events for DynamoDB | Optional CloudTrail data event logging | API-level reads and writes with actor and request context | Best Stage 4 service log candidate | Often disabled because of cost and volume [S6] |
| DynamoDB Streams / Kinesis CDC metrics | Native metrics when change data capture is enabled | Replication backlog, oldest age, failed replication counts, CDC unit consumption | Best freshness and CDC cost context | Absent if the feature is not enabled [S1][S5] |
| DescribeTable / control-plane inspection | AWS API or inventory tooling | Billing mode, GSI status, stream settings, replica layout | Explains why some metric families appear or are absent | Not a timeseries source; must be combined with metrics [S10] |

### Best-practice inference
- "No data" on replication or CDC widgets usually means global tables or Kinesis integration are not enabled, not that replication is perfectly healthy.
- "No data" on online-index widgets usually means no active GSI build is happening, which is a healthy steady-state default.
- "No data" on Contributor Insights derived pivots usually means the feature was never enabled or is not ingested into Tsuga.
- Stage 2 should treat capacity-mode-specific metrics carefully: provisioned and on-demand surfaces can coexist in documentation, but a given table often makes only one family operationally relevant at a time.
- Stage 2 confirmed that this workspace currently exposes only provisioned-capacity and account-quota metrics for DynamoDB, so any dashboard built from this bundle must be explicitly framed as capacity-only rather than full service health.

## Log intelligence (Stage 4 handoff)

### Confirmed by sources
1. **Log sources matrix**

| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|---|---|---|---|---|
| CloudTrail management events | CloudTrail Event History, S3 trail delivery, or CloudWatch Logs integration | CloudTrail JSON event | Structured | [S6] |
| CloudTrail data events for DynamoDB | Optional CloudTrail data-event logging for tables | CloudTrail JSON event with request and identity context | Structured | [S6] |
| Application consumers of DynamoDB Streams or Kinesis CDC | App logs around stream processors | App-specific JSON or text, not a DynamoDB-native format | Mixed | [S5] |

2. **Known log formats**
- **CloudTrail DynamoDB event**: JSON event with fields such as `eventSource`, `eventName`, `awsRegion`, `userIdentity`, `sourceIPAddress`, and request details. Typical event source is `dynamodb.amazonaws.com`. [S6]
- **CloudTrail data event for table access**: JSON event similar to management events, but focused on data-plane operations such as item reads and writes when data-event logging is enabled. Request shape and response elements vary by API operation. [S6]

3. **Candidate query filters for Stage 4**
- Precise: `eventSource:dynamodb.amazonaws.com AND requestParameters.tableName:*`
  Rationale: targets CloudTrail records that clearly belong to DynamoDB and have a table target.
  Risk: field names may be normalized differently in Tsuga.
- Fallback: `(message:*dynamodb.amazonaws.com* OR message:*DynamoDB*) AND (GetItem OR PutItem OR UpdateItem OR Query OR Scan)`
  Rationale: works when CloudTrail JSON is not fully normalized.
  Risk: could mix application logs mentioning DynamoDB with true CloudTrail events.

4. **Attribute mapping hints**

| Raw field | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| `awsRegion` | `context.cloud.region` | High | Stable CloudTrail field |
| `requestParameters.tableName` | `context.tablename` | High | Best Stage 4 table filter |
| `requestParameters.indexName` | `context.globalsecondaryindexname` | Medium | Present only for index-scoped operations |
| `eventName` | `context.operation` | High | Maps naturally to DynamoDB API operation |
| `recipientAccountId` | `context.cloud.account.id` | High | Good ownership and quota boundary |
| `userIdentity.arn` | `context.actor.arn` | Medium | High-cardinality, useful for investigations but not defaults |
| `sourceIPAddress` | `context.source.ip` | Medium | Useful for anomalous access paths |

5. **Parsing risks**
- CloudTrail data events for DynamoDB are optional and can be absent even in production workloads. [S6]
- Different DynamoDB APIs emit different request payload shapes, so parsers must handle missing `indexName`, transaction substructures, and batch request arrays. [S6][S8]
- Streams and Kinesis consumers are not DynamoDB-native logs; their formats come from the application or integration layer, so Stage 4 should not infer one canonical parser from DynamoDB docs alone. [S5]
- Contributor Insights exposes key-level evidence in CloudWatch graphs, but that is not a raw log stream and should not be treated as a parsable log source. [S3]

### Best-practice inference
- Stage 4 should prioritize CloudTrail if the goal is who-did-what change analysis, and application stream-processor logs if the goal is CDC failure root cause.
- If Tsuga already normalizes CloudTrail JSON fields, `context.tablename`, `context.globalsecondaryindexname`, and `context.operation` should be the first extracted keys because they align directly with the dashboard group-bys.

## Caveats and footguns
- **[table-capacity]** `SuccessfulRequestLatency` covers successful requests only. A retry storm can make clients slow even if the service latency metric looks stable. (Inference)
- **[table-capacity]** `ReturnedItemCount` and `ReturnedBytes` can rise because callers switched from point reads to broad `Query` or `Scan` patterns, not because throughput capacity is broken. [S1]
- **[table-capacity]** `SuccessfulRequestLatency` is often segmented by `Operation`; if Stage 2 does not find `context.operation`, the dashboard must not promise operation-sliced latency. [S1]
- **[table-capacity]** `ConsumedReadCapacityUnits` and `ConsumedWriteCapacityUnits` are period totals. For per-second intuition, divide the summed value by the interval length. [S1]
- **[table-capacity]** Short spikes can be muted in CloudWatch minute rollups, so "utilization looked fine" does not prove the workload never burst. [S1]
- **[account-capacity, table-capacity]** Provisioned and on-demand limit metrics are not equally relevant for every table. Showing both without mode context can confuse operators. [S1][S9]
- **[table-capacity]** Transactional APIs consume double read or write units per item compared with non-transactional operations, so a transaction-heavy rollout can look like unexplained capacity inflation. [S8]
- **[table-capacity]** Adaptive capacity can mask hotspot pain temporarily, so near-flat table-level utilization does not rule out partition pressure. [S2][S9]
- **[table-capacity]** `ThrottledRequests` increments at request level, while `ReadThrottleEvents` and `WriteThrottleEvents` can increment multiple times per request because tables and GSIs are counted separately. [S1]
- **[table-capacity]** Batch requests only increment `ThrottledRequests` when every request in the batch is throttled, so request-level throttles can understate partial pain. [S1]
- **[table-capacity]** Partition-limit throttles (`KeyRangeThroughput`) usually require key-distribution fixes, not only more table capacity. [S2][S7]
- **[table-capacity]** Contributor Insights may expose sensitive partition-key values. Do not make those default legends or dashboard filters. [S3]
- **[table-capacity]** GSI throttles can be invisible if you only chart table-level dimensions. Always preserve the optional index dimension when available. [S1][S10]
- **[table-capacity]** `ConditionalCheckFailedRequests` is often normal application behavior for optimistic locking. Treat it as correctness or contention context, not a platform outage signal by default. [S1]
- **[table-capacity]** `UserErrors` aggregates many HTTP 400 cases, including `TransactionConflict`, but excludes throughput-exceeded and conditional-check failures. The metric is broad and must be interpreted with the more specific counters. [S1]
- **[table-capacity]** `SystemErrors` is Region-account scoped and usually sparse. One spike is high-signal, but low sustained values can still matter during customer-facing incidents. [S1]
- **[account-capacity]** `PendingReplicationCount` is documented for legacy global tables. Stage 2 must verify whether it exists in this workspace before promising it in the UI. [S1][S4]
- **[account-capacity]** Replication lag metrics can be absent simply because global tables are not enabled. Missing data does not always mean telemetry failure. [S4]
- **[account-capacity]** `ConsumedChangeDataCaptureUnits`, `FailedToReplicateRecordCount`, and `ThrottledPutRecordCount` only matter if DynamoDB-to-Kinesis change data capture is enabled. [S1][S5]
- **[account-capacity]** Online index metrics are intentionally quiet outside active index builds. A blank chart here is often healthy. [S1][S10]
- **[account-capacity]** `OnlineIndexConsumedWriteCapacity` and `OnlineIndexThrottleEvents` are expected to stay at zero during index builds in current AWS docs, so `OnlineIndexPercentageProgress` is the more actionable signal. [S1]
- **[account-capacity]** GSI creation does not use Application Auto Scaling to speed up the build, so increasing minimum autoscaling targets will not shorten build time. [S10]

## Confirmed Tsuga prefixes
- `aws_dynamodb*` - **CONFIRMED** (12/12 live matches during Stage 2 preflight and catalog bootstrap)
- `aws_dynamodb_` - **CONFIRMED** (12/12 live matches; the exported family is underscore-normalized in Tsuga)

## Discovery status
- Stage 2 discovery completed: 12 DynamoDB metrics confirmed in Tsuga, all `summary` with `cumulative` temporality.
- Confirmed live families are limited to account-level provisioned-capacity ceilings and utilization plus table-level consumed and provisioned capacity.
- The following Stage 1 families are absent in this workspace: latency, throttling, user or system errors, replication or CDC, TTL, and online-index metrics.
- The live context registry is narrow: `context.env`, `context.team`, `context.cloud.region`, `context.cloud.account.id`, and `context.tablename` on table-scoped capacity metrics.
- Scalar spot-checks through Tsuga aggregation returned internal server errors, so recent-data validation is inconclusive rather than zero.

## Top sources
- [S1] https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/metrics-dimensions.html - Primary DynamoDB CloudWatch metric catalog, dimensions, and statistics.
- [S2] https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/throttling-diagnosing-workflow.html - Best official mapping from throttle reason to the right metric family.
- [S3] https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/contributorinsights_HowItWorks.html - Explains hot-key and throttled-key investigation behavior and caveats.
- [S4] https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/globaltables_monitoring.html - Official guidance for global-table replication health and lag interpretation.
- [S5] https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/streamsmain.html - Official change-data-capture options and feature boundaries.
- [S6] https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/logging-using-cloudtrail.html - Best source for Stage 4 log-source reality and event fields.
- [S7] https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/bp-partition-key-sharding.html - Official hot-partition mitigation guidance.
- [S8] https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/transaction-apis.html - Transaction semantics, conflict handling, and double-capacity caveats.
- [S9] https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/capacity-mode.html - Capacity-mode behavior and why provisioned vs on-demand must be separated.
- [S10] https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GSI.OnlineOps.html - Official GSI build behavior, monitoring, and build-time operational caveats.
