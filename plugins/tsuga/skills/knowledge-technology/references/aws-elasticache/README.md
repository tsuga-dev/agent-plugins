# AWS ElastiCache Integration Context Bundle

## Metadata
**Technology:** AWS ElastiCache
**Deployment:** managed
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** mixed
**Integration scope:** core service only
**Primary use-case:** reliability and performance

## How to use this bundle
- Use `01_aws-elasticache_metrics.csv` as the source of truth for dashboard-safe metric names, units, temporality assumptions, and safe aggregation patterns.
- Use `02_aws-elasticache_dashboard_plan.yaml` for the dashboard blueprint: sections, widgets, derived signals, explanation notes, triage chains, playbooks, and coverage intent.
- Use `03_aws-elasticache_state.yaml` for machine-readable status, assumptions, unknowns, and Stage 4 log intelligence handoff.
- Use `04_aws-elasticache_memory.md` for the readable Stage 1 handoff narrative and the Stage 2 verification order.
- Stage 2 will create `05_aws-elasticache_metric_catalog.csv` as the discovered Tsuga catalog for reconciliation, attribute validation, and coverage checks.
- Stage 4 should read this file's `Log intelligence (Stage 4 handoff)` section and `03_aws-elasticache_state.yaml` `log_intel` block first before designing any log route.

## What it is and what "good" looks like
### Confirmed by sources
AWS ElastiCache is a managed in-memory caching service that supports Valkey, Redis OSS, and Memcached, with two deployment models: serverless and self-designed node-based clusters. Serverless gives a single endpoint and automatically scales memory, compute, and network capacity, while self-designed clusters expose explicit nodes, shards, replicas, and placement choices. [How ElastiCache works](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/WhatIs.corecomponents.html), [ElastiCache components and features](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/WhatIs.Components.html)

For Valkey and Redis OSS, "good" means the cache is absorbing demand with stable read and write latency, high cache efficiency, enough headroom in engine CPU and memory, and low replica lag when replicas exist. AWS explicitly recommends watching CPU, engine CPU, swap, evictions, connections, memory, latency, replication, and traffic-management signals because these are the first indicators of impending saturation or instability. [Which Metrics Should I Monitor?](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.WhichShouldIMonitor.html), [Metrics for Valkey and Redis OSS](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.Redis.html), [Host-Level Metrics](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.HostLevel.html)

For Memcached, "good" means request and connection volume are stable, hit efficiency remains high enough for the workload, evictions are rare and explainable, and host CPU and memory are not being consumed by undersized nodes or hot keys. AWS documents Memcached-specific request, item, connection, and memory metrics at node level. [Metrics for Memcached](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.Memcached.html), [Host-Level Metrics](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.HostLevel.html)

For serverless ElastiCache, "good" means data storage and ElastiCache Processing Units stay within configured limits, pre-scaling is used ahead of sharp demand spikes, and throttling or out-of-memory behaviors never appear in production because operators have enough warning from `BytesUsedForCache` and `ElastiCacheProcessingUnits`. [How ElastiCache works](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/WhatIs.corecomponents.html), [Scaling ElastiCache](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Scaling.html)

Top incident shape 1: cache inefficiency or memory pressure. Start in `ec-redis-efficiency` or `ec-memcached-efficiency` first to determine whether misses, evictions, or memory headroom changed before latency. Top incident shape 2: write interruption or replica instability in Valkey/Redis. Start in `ec-redis-resilience`. Top incident shape 3: serverless throttling or scaling-limit pressure. Start in `ec-serverless-capacity`.

### Best-practice inference
The technology name is broader than a single metric family. A useful ElastiCache dashboard should treat Valkey/Redis OSS, Memcached, and serverless as explicit sub-surfaces rather than collapsing them into one undifferentiated cache view, because replication, log support, scaling behavior, and even the meaning of CPU pressure differ materially across them.

For first-response dashboards, cache efficiency matters more than raw request volume. A traffic spike with stable hit rate and stable latency is often a healthy growth event; a flat request rate with falling hit rate or rising evictions is usually more urgent because it signals a working set or sizing problem.

The dashboard should preserve ownership boundaries: host-level metrics answer whether the managed node is under OS pressure, engine metrics answer whether the cache engine is the bottleneck, and serverless ECPU metrics answer whether AWS-managed compute elasticity is nearing configured limits.

## Key concepts
### Glossary
| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| Serverless cache | ElastiCache deployment with automatic capacity management and a single endpoint | Headroom is tracked through storage and ECPU, not node counts | ec-serverless-capacity |
| Self-designed cluster | Node-based ElastiCache deployment where operators choose node size and count | Capacity planning and blast radius are explicit operator concerns | ec-fleet-health |
| Cache node | Smallest ElastiCache compute and memory unit | Main host-level failure and saturation boundary | ec-fleet-health |
| Shard | Valkey/Redis partition of data across node groups | Write scaling and hotspot analysis depend on shard distribution | ec-redis-resilience |
| Replication group | Valkey/Redis grouping of primaries and replicas | High availability and replica lag analysis anchor here | ec-redis-resilience |
| Primary node | Read/write Redis or Valkey node | Write latency and failover ownership start here | ec-redis-resilience |
| Read replica | Read-only replica following a primary asynchronously | Replica lag is the early warning for stale reads and failover risk | ec-redis-resilience |
| Configuration endpoint | Entry point clients use to discover topology | Connection failures here can affect the whole cache surface | ec-fleet-health |
| Reader endpoint | Redis endpoint that spreads reads across replicas | Useful when demand is read-heavy and replica lag matters | ec-redis-resilience |
| Auto Discovery | Memcached mechanism that lets clients learn current node endpoints | Client behavior during scale events depends on this being used correctly | ec-memcached-efficiency |
| Cache hit rate | Share of lookups served from cache instead of missing | Best top-line efficiency signal for caching value | ec-redis-efficiency |
| Eviction | Removal of non-expired items due to memory pressure | Strong sign that the working set no longer fits or TTL policy is wrong | ec-redis-efficiency |
| Freeable memory | OS memory that the host can reclaim | Low headroom often precedes instability before the engine reports it directly | ec-fleet-health |
| Engine CPU | CPU used by the Valkey/Redis engine thread | Better saturation indicator than host CPU on larger Redis nodes | ec-redis-efficiency |
| Host CPU | CPU consumed by the whole cache host | Important when background managed processes compete with the engine | ec-fleet-health |
| Successful read latency | Latency of successful read commands | Measures the user-facing cost of cache reads | ec-redis-efficiency |
| Successful write latency | Latency of successful write commands | Measures mutation path cost and persistence/replication stress | ec-redis-resilience |
| Replication lag | Delay between primary and replica applying updates | Direct indicator of stale-read and failover exposure | ec-redis-resilience |
| Traffic management active | Redis signal showing ElastiCache is shedding or shaping workload for stability | Indicates undersized nodes or bandwidth constraints | ec-redis-resilience |
| ECPU | ElastiCache Processing Unit for serverless compute billing and scaling | Main compute-intensity signal for serverless caches | ec-serverless-capacity |
| Data tiering | Redis/Valkey feature that stores colder data on SSD | Changes memory semantics and adds disk read/write signals | ec-redis-efficiency |
| Slow log | Redis/Valkey log stream of slow commands | Best source for query-pattern root cause after metrics show latency | ec-redis-resilience |
| Engine log | Redis/Valkey operational log stream | Best source for warnings, notices, and engine-side anomalies | ec-redis-resilience |
| SNS event notification | ElastiCache control-plane event stream | Best source for topology changes, replacements, and scaling events | ec-redis-resilience |

### Concept Map
Application -> connects to -> cache endpoint (why: every cache incident starts with whether clients can still reach the cache)
Cache endpoint -> resolves to -> serverless proxy layer or node endpoints (why: connection behavior differs by deployment model)
Serverless proxy layer -> routes requests to -> backend cache nodes (why: client topology is hidden but scaling pressure still exists underneath)
Self-designed cluster -> contains -> cache nodes (why: host saturation and blast radius are node scoped)
Valkey/Redis cluster -> partitions data into -> shards (why: write scaling and hotspots are shard dependent)
Shard -> contains -> primary node (why: writes and failover ownership land on the primary)
Shard -> contains -> read replicas (why: read scale and replica lag depend on replica health)
Primary node -> asynchronously replicates to -> read replica (why: stale reads and failover safety depend on lag)
Memcached cluster -> partitions data across -> nodes (why: node loss or hot key imbalance can create partial misses)
Client auto discovery -> refreshes -> Memcached node map (why: scaling events are only safe if clients learn new nodes)
Working set size -> drives -> memory consumption (why: memory pressure is the root cause of many cache incidents)
Memory consumption -> triggers -> evictions when max memory is reached (why: eviction spikes usually mean cache value is falling)
Cache misses -> increase -> backend dependency load (why: cache degradation propagates into downstream databases)
Engine CPU -> constrains -> Redis command throughput (why: Redis is effectively single-threaded for engine work)
Host CPU -> includes -> engine work plus managed background processes (why: host overload can exist even when engine CPU is moderate)
TrafficManagementActive -> indicates -> node cannot process current incoming load safely (why: this is an undersizing symptom, not a healthy steady state)
Successful request latency -> reflects -> command execution cost (why: rising latency is the user-visible outcome of saturation)
Replication lag -> grows when -> primary or network cannot keep replicas caught up (why: read consistency and failover posture degrade)
Serverless ECPU -> grows with -> transferred data and compute cost per command (why: this is the serverless compute saturation and cost proxy)
Serverless storage limits -> cap -> retained data size (why: nearing limits can cause eviction or OOM behavior)
Slow log entries -> reveal -> expensive commands and hot access patterns (why: metrics show symptoms; logs show command-level cause)
Engine logs -> reveal -> warnings and operational events (why: useful for correlation when behavior changes abruptly)
SNS events -> reveal -> topology, scaling, and replacement changes (why: control-plane events explain sudden metric shifts)
Availability Zone placement -> affects -> resilience and failover blast radius (why: replicas in one AZ do not provide real HA)
Context filters -> map to -> environment, team, region, engine, cluster, replica group (why: triage needs safe ownership and topology slicing)

### Entities and dimensions
#### Confirmed by sources
| Entity / dimension | Why useful | Cardinality risk | Safe top-N suggestion |
|---|---|---|---|
| CacheClusterId | Primary identity for node-based cluster telemetry and logs | Low to medium | Top 20 |
| CacheNodeId | Needed for host-level and log-level node troubleshooting | Medium | Top 20 |
| ReplicationGroupId | Primary Redis HA boundary | Low | Top 20 |
| NodeGroupId / shard | Needed for Redis hotspot and replication topology analysis | Medium | Top 20 |
| Engine | Separates Valkey, Redis OSS, and Memcached behavior | Very low | Top 5 |
| Tier | Distinguishes memory vs SSD for data-tiered Redis metrics | Very low | Top 2 |
| Availability Zone | Main blast-radius split for HA and placement | Low | Top 6 |
| Region | Required for multi-region or global datastore interpretation | Low | Top 10 |
| Serverless cache name | Primary identity for serverless telemetry | Low | Top 20 |
| Log type | Distinguishes slow log vs engine log | Very low | Top 5 |
| Command family | Useful for latency drilldowns if exported | Medium to high | Top 15 |
| Event name | Best control-plane change grouping | Medium | Top 20 |

#### Best-practice inference
| Entity / dimension | Why useful | Cardinality risk | Safe top-N suggestion |
|---|---|---|---|
| context.team | Ownership routing | Low | Top 20 |
| context.env | Production vs staging split | Low | Top 10 |
| context.cloud.account.id | Multi-account blast-radius separation | Low | Top 20 |
| context.client.address | Useful for debugging abusive clients, but often too high cardinality | High | Do NOT group-by by default |
| key / command text | Useful in logs only, not metrics | Very high | Do NOT group-by |
| security group | Helpful for access incidents if present | Medium | Top 20 |

### Tsuga field mapping
#### Confirmed by sources
| Vendor / exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| CacheClusterId | `context.cacheclusterid` | Optional |
| CacheNodeId | `context.cachenodeid` | Optional |
| ReplicationGroupId | `context.replicationgroupid` | Optional |
| NodeGroupId / shard | `context.nodegroupid` | Optional |
| Availability Zone | `context.cloud.availability_zone` | Optional |
| Region | `context.cloud.region` | Optional |
| Engine | `context.engine` | Optional |
| Tier | `context.tier` | Optional |
| Log type | `context.log.type` | Optional |

#### Best-practice inference
| Vendor / exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| Serverless cache name | `context.serverless_cache.name` | Optional |
| Cluster / cache display name | `context.cache.name` | Optional |
| Account ID | `context.cloud.account.id` | Optional |
| Team | `context.team` | Must-exist |
| Environment | `context.env` | Must-exist |
| Service name | `context.service.name` | Optional |

### Stage 2 discovery update
- The live Tsuga catalog confirms `context.env`, `context.team`, `context.cloud.region`, `context.cloud.account.id`, `context.cacheclusterid`, and `context.cachenodeid` across the discovered `aws_elasticache_*` family.
- `context.replicationgroupid`, `context.nodegroupid`, and `context.role` are present only on a small Redis-family subset, notably `aws_elasticache_engine_cpu_utilization` and the counted-for-evict memory/capacity metrics.
- `context.engine` and `context.serverless_cache.name` were not observed in the live metric catalog, so they should not be used as global filters in Stage 3.

## Golden signals
### Confirmed by sources
| Signal | What it means for ElastiCache | Typical causes when degraded | Best telemetry sources | What people page on | Section questions |
|---|---|---|---|---|---|
| Traffic | Connections, commands, bytes, and serverless ECPU showing load shape | Release spike, hot key, backend fallback, uneven key distribution | `CurrConnections`, Memcached `NewConnections`, host network, `ElastiCacheProcessingUnits` | Sudden demand increase, throttling, traffic shape change | "Did demand change?" "Which engine or cache is hottest?" |
| Errors | Miss inflation, auth failures, error count, traffic management, OOM-like symptoms | Working set overflow, auth/config drift, undersized nodes, limit exhaustion | `CacheMisses`, `ErrorCount`, `AuthenticationFailures`, `TrafficManagementActive`, SNS events | Miss storm, throttling, write failures, auth failures | "Is the cache still returning value?" "Is the engine rejecting or shaping work?" |
| Latency | Read and write command cost as seen in successful command latency | CPU saturation, slow commands, replication pressure, hot keys | `SuccessfulReadRequestLatency`, `SuccessfulWriteRequestLatency`, slow log | Sustained latency increase on successful commands | "Are users paying more for cache operations?" |
| Saturation | CPU, memory, storage, replica lag, and ECPU/storage-limit pressure | Node undersizing, poor TTL policy, replication backlog, serverless max limits | `EngineCPUUtilization`, `CPUUtilization`, `FreeableMemory`, `DatabaseMemoryUsagePercentage`, `ReplicationLag`, `BytesUsedForCache`, `ElastiCacheProcessingUnits` | Headroom collapse, evictions, replica lag, throttling risk | "What resource is binding first?" "Is this recoverable by scale-out or only by design changes?" |

### Best-practice inference
- For cache systems, traffic is only useful when paired with efficiency. High traffic with high hit rate is often healthy; moderate traffic with collapsing hit rate is usually the more operationally important signal.
- Replication lag belongs under saturation for Redis/Valkey, not just availability, because lag typically grows when primaries or networks are already overloaded.
- For serverless caches, ECPU is both a cost and performance signal. It should be treated as a leading indicator for throttling risk when explicit usage limits are configured.

## Telemetry sources
### Confirmed by sources
| Source type | How collected | What it provides | Pros / cons | Common pitfalls |
|---|---|---|---|---|
| ElastiCache engine metrics for Valkey / Redis OSS | Native AWS/ElastiCache CloudWatch metrics, mostly derived from `INFO` | Cache efficiency, latency, CPU, memory, replication, traffic management | Richest engine-specific signal set / only valid for Redis-family caches | Some metrics are replica-only, data-tiering-only, or engine-version dependent [Metrics for Valkey and Redis OSS](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.Redis.html) |
| ElastiCache engine metrics for Memcached | Native AWS/ElastiCache CloudWatch metrics from Memcached stats | Connections, request volume, hit/miss, evictions, item and memory behavior | Clean Memcached-specific request semantics / no replication semantics | `UnusedMemory` is not true free memory and evictions can still happen [Metrics for Memcached](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.Memcached.html) |
| Host-level metrics | AWS/ElastiCache CloudWatch host metrics every 60s | CPU, freeable memory, network IO, CPU credit behavior | Cross-engine baseline / less specific than engine metrics | Host CPU and engine CPU mean different things on Redis-family caches [Host-Level Metrics](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.HostLevel.html) |
| Serverless scaling metrics | CloudWatch serverless usage metrics | `BytesUsedForCache`, `ElastiCacheProcessingUnits`, limit proximity | Best serverless capacity picture / less topology detail than node-based clusters | Usage limits can create throttling or OOM-like behavior before infra auto-scales enough [Scaling ElastiCache](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Scaling.html), [How ElastiCache works](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/WhatIs.corecomponents.html) |
| Log delivery | Redis/Valkey slow log or engine log to CloudWatch Logs or Firehose in JSON or TEXT | Slow commands, engine warnings, client origin, command details | Strong root-cause detail / supported only for Redis-family engines and certain versions | Slow log has finite retention and delivery may miss older entries if `slowlog-max-len` is too small [Log delivery](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Log_Delivery.html) |
| SNS event notifications | ElastiCache control-plane notifications to SNS | Node replacement, provisioning, scaling, security-group and parameter changes | Explains topology or config change causality / not continuous performance telemetry | Topic and region/account requirements can silently prevent expected notifications [Event Notifications and Amazon SNS](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/ElastiCacheSNS.html) |

### Best-practice inference
- "No data" can mean different things by surface: Redis replica lag may be absent because there are no replicas; slow logs may be absent because log delivery is disabled; serverless ECPU may be absent if the environment does not use serverless caches at all.
- Stage 2 should verify whether Tsuga exposes one generic `aws_elasticache_*` namespace or splits serverless and node-based surfaces more explicitly.

## Log intelligence (Stage 4 handoff)
### Confirmed by sources
1. **Log sources matrix**

| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|---|---|---|---|---|
| Redis / Valkey slow log | CloudWatch Logs or Firehose via log delivery | JSON or TEXT slow-log entries | Structured or semi-structured | [Log delivery](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Log_Delivery.html) |
| Redis / Valkey engine log | CloudWatch Logs or Firehose via log delivery | JSON or TEXT engine log entries | Structured or semi-structured | [Log delivery](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Log_Delivery.html) |
| ElastiCache SNS events | SNS delivery from ElastiCache control plane | Event notification messages | Structured enough for event routing | [Event Notifications and Amazon SNS](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/ElastiCacheSNS.html) |
| Memcached engine logs | Unknown in AWS-managed delivery docs | Unknown | Unknown | No equivalent Memcached log-delivery page found in primary docs reviewed |

2. **Known log formats**
- `Redis/Valkey slow log`
  - Sample shape: cluster id, node id, log entry id, unix timestamp, execution duration in microseconds, command, client address, and optional client name.
  - Delimiter notes: can be emitted as JSON or TEXT.
  - Timestamp pattern: Unix timestamp for slow-log event time.
  - Quoting behavior: command text is sanitized so real key/value arguments are replaced rather than emitted verbatim.
  - Optional fields: client name is only present if set. [Log delivery](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Log_Delivery.html)
- `Redis/Valkey engine log`
  - Sample shape: cluster id, node id, log level, UTC timestamp, role, and message body.
  - Timestamp pattern: `DD MMM YYYY hh:mm:ss.ms UTC`.
  - Quoting behavior: plain text or JSON depending on delivery configuration.
  - Optional fields: role and message content vary with engine state. [Log delivery](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Log_Delivery.html)

3. **Candidate query filters for Stage 4**
- Precise: `context.service.name:"aws-elasticache" AND context.cacheclusterid:* AND (context.log.type:"slow-log" OR context.log.type:"engine-log")`
  - Rationale: targets Redis/Valkey log delivery with both identity and log-type boundaries.
  - Risk: assumes Tsuga already normalizes service name and log-type fields.
- Fallback: `"CacheClusterId" AND ("slowlog" OR "LogLevel" OR "ClientAddress")`
  - Rationale: broad text search that can catch raw JSON or text delivery payloads.
  - Risk: may mix different AWS log streams and misses Memcached entirely.

4. **Attribute mapping hints**

| Raw field | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| CacheClusterId | `context.cacheclusterid` | High | Explicitly documented in slow and engine log contents |
| CacheNodeId | `context.cachenodeid` | High | Explicitly documented in slow and engine log contents |
| Duration | `context.db.query.duration_us` | High | Slow log duration is in microseconds |
| Command | `context.db.operation` | Medium | Prefer operation family rather than full command text for low cardinality |
| ClientAddress | `context.client.address` | Medium | May need splitting into host and port |
| ClientName | `context.client.name` | Medium | Optional field |
| Log level | `context.level` | High | Engine log has documented levels |
| Role | `context.cache.role` | Medium | Useful for primary vs replica interpretation if present |
| Event name | `context.event.name` | Medium | For SNS event routes |

5. **Parsing risks**
- Slow log delivery is only supported for Valkey 7.x+ and Redis OSS 6.0+; engine log delivery is only supported for Valkey 7.x+ and Redis OSS 6.2+. [Log delivery](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Log_Delivery.html)
- Slow log retrieval is bounded by `slowlog-max-len`, so a busy system can drop older slow-log entries before delivery. [Log delivery](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Log_Delivery.html)
- JSON and TEXT are both supported, so Stage 4 should confirm the actual sink format before committing to a parser. [Log delivery](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Log_Delivery.html)
- Memcached log delivery is not confirmed in the primary docs reviewed, so Stage 4 should not fabricate a Memcached parser path.
- SNS event messages and engine logs are operationally useful but semantically different; they should not share one generic parser without a split condition.

### Best-practice inference
- Prefer routing Redis/Valkey slow logs separately from engine logs because their target attributes and cardinality budgets differ.
- If only SNS events are present, Stage 4 should build an event route rather than pretending command-level logs exist.
- Full command text should stay as raw log content or an optional low-priority attribute, not a default group-by key.

## Caveats and footguns
- **[ec-fleet-health]** `CPUUtilization` and `EngineCPUUtilization` are not interchangeable for Valkey/Redis OSS; host CPU includes background managed processes while engine CPU tracks the cache engine thread. ([Host-Level Metrics](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.HostLevel.html), [Metrics for Valkey and Redis OSS](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.Redis.html))
- **[ec-fleet-health]** On small Redis-family nodes, watching only engine CPU can hide host overload from background processes. ([Which Metrics Should I Monitor?](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.WhichShouldIMonitor.html))
- **[ec-fleet-health]** Host-level metrics are emitted per cache node every 60 seconds, so brief spikes can disappear in coarse windows. ([Host-Level Metrics](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.HostLevel.html))
- **[ec-fleet-health]** Multi-AZ for Valkey/Redis OSS only helps when replicas exist in different Availability Zones. ([Minimizing downtime in ElastiCache by using Multi-AZ with Valkey and Redis OSS](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/AutoFailover.html))
- **[ec-redis-efficiency]** `CacheHitRate` can fall because of misses, evictions, or expired keys; it does not by itself distinguish which one changed. ([Metrics for Valkey and Redis OSS](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.Redis.html))
- **[ec-redis-efficiency]** Data-tiered Redis metrics can carry a `Tier` dimension, so collapsing memory and SSD signals together can hide where pressure really lives. ([Metrics for Valkey and Redis OSS](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.Redis.html))
- **[ec-redis-efficiency]** `DatabaseMemoryUsagePercentage` and `DatabaseCapacityUsagePercentage` are not equivalent once data tiering is enabled. ([Metrics for Valkey and Redis OSS](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.Redis.html))
- **[ec-redis-efficiency]** A healthy cache can still show high `CurrConnections` because ElastiCache itself uses some monitoring connections. ([Metrics for Valkey and Redis OSS](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.Redis.html))
- **[ec-redis-efficiency]** `BytesUsedForCache` includes dataset, buffers, and other memory purposes, so it is broader than "live items only." ([Metrics for Valkey and Redis OSS](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.Redis.html))
- **[ec-redis-resilience]** `ReplicationLag` is replica-only; absence may mean there is no replica rather than that replication is healthy. ([Metrics for Valkey and Redis OSS](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.Redis.html))
- **[ec-redis-resilience]** `TrafficManagementActive` is a boolean symptom of undersizing or bandwidth stress, not a normal operating mode to ignore. ([Metrics for Valkey and Redis OSS](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.Redis.html))
- **[ec-redis-resilience]** Successful read and write latency track only successful commands; failing or throttled paths can be underrepresented. ([Metrics for Valkey and Redis OSS](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.Redis.html))
- **[ec-redis-resilience]** Background save activity can degrade performance and can be misread as generic latency regression if `SaveInProgress` is not checked. ([Metrics for Valkey and Redis OSS](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.Redis.html))
- **[ec-memcached-efficiency]** Memcached is multi-threaded, so CPU interpretation differs from Redis-family guidance. ([Which Metrics Should I Monitor?](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.WhichShouldIMonitor.html))
- **[ec-memcached-efficiency]** `UnusedMemory` is not true free memory; evictions can still occur while `UnusedMemory` is nonzero. ([Metrics for Memcached](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.Memcached.html))
- **[ec-memcached-efficiency]** Memcached has no Redis-style replica lag or failover metrics, so using Redis HA playbooks on Memcached is wrong. ([ElastiCache components and features](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/WhatIs.Components.html))
- **[ec-memcached-efficiency]** Memcached clusters repartition data when nodes are added or removed, so hit-rate changes around scale events may be expected. ([ElastiCache components and features](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/WhatIs.Components.html))
- **[ec-serverless-capacity]** Hitting a serverless data-storage maximum can trigger eviction or OOM behavior; hitting an ECPU maximum can throttle requests. ([Scaling ElastiCache](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Scaling.html))
- **[ec-serverless-capacity]** Serverless pre-scaling changes may take up to 60 minutes to become available, so they are not instantaneous incident mitigations. ([Scaling ElastiCache](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Scaling.html))
- **[ec-serverless-capacity]** Minimum serverless limits incur cost even if actual usage stays below them. ([Scaling ElastiCache](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Scaling.html))
- **[ec-serverless-capacity]** Aggregate serverless scale can still be uneven per slot; skewed key distribution can create hot-slot symptoms before cache-wide metrics look extreme. ([Scaling ElastiCache](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Scaling.html))
- **[ec-redis-resilience]** Slow and engine log delivery are Redis-family features with engine-version prerequisites, so a missing log stream may be a feature gap rather than an ingestion problem. ([Log delivery](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Log_Delivery.html))
- **[ec-redis-resilience]** SNS notifications require same-account, same-region topics and do not work effectively with encrypted topics in the described configuration. ([Event Notifications and Amazon SNS](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/ElastiCacheSNS.html))

## Confirmed Tsuga prefixes
- `aws_elasticache_*` — **CONFIRMED** (77 live metrics found in the last 24 hours via `tools/tsuga_search_metrics.py '^aws_elasticache_.*'` and catalog bootstrap)

## Discovery status
Discovery complete for Stage 2 bootstrap and reconciliation:
- 77 live `aws_elasticache_*` metrics found in Tsuga over the last 24 hours.
- 32 metrics are now represented in `01_aws-elasticache_metrics.csv` and confirmed live.
- 10 Stage 1 metrics are missing from the live environment, all in the Memcached-specific or serverless-specific surface.
- The discovered environment is effectively Redis-family plus host-level ElastiCache telemetry; no Memcached get/hit metrics and no serverless ECPU/storage metrics were found.
- Spot-check aggregation against the raw scalar endpoint returned HTTP 400, so point-in-time scalar validation was inconclusive; the live catalog itself still proves recent presence because discovery used a 24-hour window.

Remaining unknowns after discovery:
- Whether any Memcached or serverless metrics exist outside the last 24-hour window or in a different account / environment slice.
- Whether Redis/Valkey slow logs, engine logs, or only SNS events are available for Stage 4.
- Whether command-family latency summaries are operationally useful enough to promote into Stage 3 enrichment widgets.

## Top sources
- https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/WhatIs.corecomponents.html
  Why: best high-level explanation of deployment models, serverless behavior, and ECPU semantics.
- https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/WhatIs.Components.html
  Why: grounds nodes, shards, replication groups, endpoints, and Memcached cluster behavior.
- https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.Redis.html
  Why: source of truth for Valkey/Redis OSS metric names and meanings.
- https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.Memcached.html
  Why: source of truth for Memcached metric names and meanings.
- https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.HostLevel.html
  Why: defines cross-engine host CPU, memory, and network metrics and sampling cadence.
- https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheMetrics.WhichShouldIMonitor.html
  Why: AWS's operational prioritization of which metrics matter most.
- https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Log_Delivery.html
  Why: authoritative for Redis/Valkey slow log and engine log support, fields, and formats.
- https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/AutoFailover.html
  Why: confirms Multi-AZ and replica prerequisites for Redis/Valkey HA.
- https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/ElastiCacheSNS.html
  Why: authoritative event-notification source for operational changes and route ideas.
- https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Scaling.html
  Why: defines serverless scaling, ECPU and storage limits, throttling risk, and pre-scaling behavior.
