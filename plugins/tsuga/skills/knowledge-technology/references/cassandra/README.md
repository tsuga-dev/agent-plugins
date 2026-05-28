# Cassandra Integration Context Bundle

## Metadata

**Technology:** Cassandra
**Deployment:** self-hosted
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** mixed (OTel JMX receiver primary; Prometheus JMX exporter alternative)
**Integration scope:** core service only
**Primary use-case:** reliability and performance

---

## How to use this bundle

- `01_cassandra_metrics.csv` — source of truth for metrics, units, temporality, safe aggregation, group-by recommendations
- `02_cassandra_dashboard_plan.yaml` — dashboard structure: sections, widgets, derived signals, explanation notes, triage chains, playbooks
- `03_cassandra_state.yaml` — machine-readable state, assumptions list, unknowns with actionable context
- `04_cassandra_memory.md` — human-readable Stage 1 summary and handoff narrative for Stage 2

Stage 2 will create `05_cassandra_metric_catalog.csv` as the discovered metric catalog for reconciliation and deep-dive coverage checks.

Stage 4 should read this file's "Log intelligence (Stage 4 handoff)" section and `03_cassandra_state.yaml` `log_intel` before designing log routes.

---

## What it is and what "good" looks like

Cassandra is a distributed wide-column NoSQL database engineered for high availability and linear horizontal scalability with no single point of failure. Nodes form a peer-to-peer ring; data is partitioned via consistent hashing and replicated across N nodes per replication factor. It is typically deployed self-hosted on bare metal or Kubernetes, accessed via CQL (Cassandra Query Language) over native transport (default port 9042).

**Confirmed by sources:**
"Good" Cassandra: read/write p99 latencies below 10ms for point queries (application-dependent); zero dropped messages; compaction backlog (pending tasks) below 10 per node; heap utilization 50–70% with GC stop-the-world pauses under 200ms per minute; key cache hit rate above 80%. [Datadog Cassandra monitoring guide; Cassandra docs]

**Best-practice inference:**
Top 3 incident shapes and first dashboard sections to check:
1. **Slow reads / p99 latency degradation** → "Read Latency" first (magnitude), then "Compaction" (SSTable count forcing extra disk seeks), then "Memory & GC" (stop-the-world pauses blocking all operations)
2. **Node overload / dropped messages** → "Errors & Dropped Messages" first, then "Thread Pools" (pending tasks spike before drops occur), then "Throughput" (confirm traffic surge)
3. **Node unavailability / replication risk** → "Cluster Health" first (storage load per node, hints accumulation), then "Storage & Hints" (growing hints = node is down), then "Compaction" (overwhelmed surviving nodes)

---

## Key concepts

### Glossary

| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| Keyspace | Top-level namespace defining replication strategy and replication factor | Wrong replication factor = data loss risk under failure | cluster-health, storage-hints |
| Table (ColumnFamily) | Schema object within a keyspace; rows partitioned by partition key | High tombstone count or large partitions directly degrade read performance | read-latency, compaction |
| SSTable | Immutable on-disk file; Cassandra never updates data in-place | Too many SSTables = read amplification; compaction merges them back | compaction, read-latency |
| Memtable | In-memory write buffer; flushed to SSTable on overflow or commit log size threshold | Memtable flush triggers compaction; large memtables cause heap pressure | memory-gc, write-latency |
| Commit Log | Write-ahead log ensuring durability before memtable flush | Disk I/O saturation on commit log path directly stalls writes | write-latency, storage-hints |
| Compaction | Background process that merges SSTables; reclaims tombstone space | Compaction backlog growing = reads scan more SSTables = read latency degrades | compaction |
| Tombstone | Deletion marker that must be scanned then garbage-collected via compaction | Excessive tombstones cause read latency spikes and WARN/ABORT query failures | read-latency, compaction |
| Gossip | Peer-to-peer protocol (port 7000/7001) for node failure detection and cluster state | Node detection lag = split brain risk; drives UP/DOWN state propagation | cluster-health |
| Nodetool | CLI for cluster management (status, repair, ring state) | `nodetool status` is the ground truth for node membership state | cluster-health |
| Repair | Process ensuring data consistency across replicas | Overdue repairs = stale data risk; repair adds compaction load | compaction, storage-hints |
| Bloom Filter | Probabilistic structure to avoid unnecessary SSTable seeks during reads | High false positive ratio = unnecessary disk I/O on every read | cache-efficiency, read-latency |
| Key Cache | Caches the partition offset in SSTable for frequently-read keys | High hit rate eliminates expensive index seeks; meaningful for read-heavy workloads | cache-efficiency |
| Row Cache | Caches entire serialized rows in memory; disabled by default | Only beneficial for small, hot rows; large rows make it counterproductive | cache-efficiency |
| Coordinator | Node that receives a client request and routes to replica nodes | Coordinator hotspot = one node handling disproportionate routing load | throughput |
| Replica | Node storing a copy of data for a partition token range | Down replica + tight consistency level = availability degradation | cluster-health |
| Consistency Level | Per-query setting controlling how many replicas must respond | CL=ONE tolerates 2 down replicas with RF=3; CL=ALL requires all up | errors-dropped |
| Dropped Messages | Messages that timed out before processing and were discarded | Non-zero drop rate = critical signal; node is overloaded or GC-stalled | errors-dropped |
| Hint | Temporarily stored mutation for a down replica, replayed when it recovers | Growing hint backlog = a node is down; large hints = slow or failing recovery | storage-hints |
| Thread Pool | Task queue for each Cassandra processing stage (ReadStage, MutationStage, etc.) | Pending tasks accumulate before drops occur; each pool has specific responsibility | thread-pools |
| Token Ring | Consistent hash ring distributing partition ownership to nodes | Uneven token distribution (vnode imbalance) = hot nodes and latency skew | cluster-health, throughput |
| Speculative Retry | Sending request to second replica before first responds | High speculative rate = tailing latency from slow replicas; costly for replica load | errors-dropped, read-latency |
| Read Repair | Synchronizing inconsistent replicas detected during a read operation | Read repair overhead inflates tail latency; heavy on high-replication tables | read-latency |
| CAS / LWT | Lightweight transaction via Paxos (compare-and-set) | CAS is ~4x more expensive than normal read/write; avoid on hot paths | write-latency |
| Compaction Strategy | STCS (write-heavy), LCS (read-heavy), TWCS (time-series, window-based) | Wrong strategy for workload = SSTable explosion or compaction amplification | compaction |
| snitch | Component defining network topology (datacenter, rack assignments) | Misconfigured snitch = cross-DC reads; wrong DC routing | cluster-health |

### Concept Map

```
Client -> CQL TCP:9042 -> Coordinator Node
  (why: entry point; coordinator routes to data-owning replicas)

Coordinator Node -> consistent_hash(partition_key) -> target Replica Nodes
  (why: determines which nodes own the data; wrong routing = cross-DC reads)

Coordinator Node -> Gossip heartbeat -> all Peer Nodes
  (why: failure detection; drives UP/DOWN/LEAVING state propagation)

Client Request -> Thread Pool queue (ReadStage|MutationStage|etc.) -> Worker threads
  (why: thread pool saturation is the first saturation signal before drops)

Thread Pool pending_tasks growing -> timeout threshold -> dropped message
  (why: dropped messages directly follow thread pool exhaustion)

Write Request -> Commit Log (disk, synchronous) + Memtable (heap, async)
  (why: durability via WAL; Memtable enables fast write path)

Memtable -> flush threshold reached -> SSTable written to disk
  (why: flush = disk write burst; triggers background compaction scheduling)

Multiple SSTables accumulate -> Compaction triggered -> fewer merged SSTables
  (why: read amplification control; removes tombstones; reclaims disk space)

Read Request -> Bloom Filter check (per SSTable) -> (false positive or definite miss) -> SSTable seek
  (why: BF false positives = unnecessary disk I/O; high false ratio = degraded reads)

Read Request -> Key Cache check -> (hit) -> direct SSTable offset read
  (why: key cache eliminates expensive partition index seek)

High Compaction Pending -> many SSTables unmerged -> N disk seeks per read -> latency spike
  (why: compaction backlog is the most direct Cassandra-specific cause of read latency degradation)

JVM GC stop-the-world pause -> all thread pools stall -> latency spike across all operations
  (why: GC pauses are the primary cause of sudden latency "steps" in Cassandra)

Heap pressure -> more frequent GC -> longer major GC pauses -> dropped messages
  (why: heap pressure creates a cascade to drops; heap utilization is leading indicator)

Node DOWN -> coordinator queues hints for that node -> hint store grows
  (why: hints = data safety net during outages; large hint store = slow recovery)

Hints In Progress growing -> node down and not recovering -> potential data gap risk
  (why: if hints TTL expires before node recovers, mutations are permanently lost)

High tombstone count in table -> read query scans N tombstones -> WARN threshold hit -> query slow/fail
  (why: tombstone accumulation is a silent killer of read performance)

Table-level coordinator.read high on one node -> coordinator hotspot -> uneven load
  (why: CQL load balancing misconfiguration causes single-node overload)

CAS (LWT) write -> Paxos 4-phase commit (prepare + promise + accept + commit) -> 4x latency vs normal write
  (why: LWT must be tracked separately; its latency profile is fundamentally different)
```

### Entities and dimensions

| Entity/Dimension | Why useful | Cardinality risk | Safe top-N | Notes |
|---|---|---|---|---|
| `host` | Per-node isolation; Cassandra performance is inherently node-specific | Medium (scales with cluster size) | 20 | Primary split dimension for all metrics |
| `keyspace` | Identifies which application's data is affected | Low-medium (few per cluster) | 16 | Required context for table-level metrics |
| `table` / `columnfamily` | Identifies exact table contributing to latency or compaction load | Medium-high (many tables possible) | 20 | Always pair with keyspace |
| `datacenter` | Multi-DC routing isolation; regional failure isolation | Low (2–5 DCs typical) | 10 | Critical for multi-DC setups; single-DC can omit |
| `operation` | Read vs write vs range_slice vs CAS; different cost and latency profiles | Very low (6 fixed values) | 6 | Prefer filter over group-by for simple split |
| `pool.name` | Thread pool identity (ReadStage, MutationStage, CompactionExecutor, etc.) | Low (10–15 fixed names) | 15 | Group-by is safe; bounded and stable |
| `cache_result` | hit / miss / hit_out_of_range for row/key cache | Very low (3 values) | 3 | Use as filter in derived signal formula |
| `percentile` | Pre-aggregated percentile values (50p, 99p, max) | Very low (3 values) | 3 | Filter to desired percentile; do NOT group-by |
| `gc.action` | Minor vs major GC type | Very low (2–3 values) | 3 | Group-by for GC type breakdown |
| `status` | Error status codes for client.request.error.count | Low (few error types: Timeout, Unavailable, etc.) | 10 | Group-by for error classification |
| `context.env` | Environment filter (prod/staging) | Very low | N/A | Dashboard-level filter; always include |
| `context.team` | Owning team filter | Low | N/A | Dashboard-level filter; always include |
| `context.k8s.namespace.name` | Kubernetes namespace isolation | Low-medium | 20 | Group-by only in multi-namespace deployments |
| `context.scope.name` | OTel instrumentation scope identifier | Very low | N/A | Do NOT group-by; use as filter if needed to isolate Cassandra metrics from JVM metrics |

**Do NOT group-by:** `context.scope.name` (implementation detail), raw IP addresses, JMX object name suffixes.

### Tsuga field mapping

**Confirmed by sources:** OTel JMX Cassandra receiver attribute names: https://github.com/open-telemetry/opentelemetry-java-contrib/blob/main/jmx-metrics/docs/target-systems/cassandra.md

**Best-practice inference:** The `context.*` Tsuga key names are inferred based on OTel attribute naming and standard Tsuga conventions. Stage 2 discovery MUST confirm these field names in live Tsuga data.

| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| `host` (JMX hostname) | `context.host` | Must-exist for per-node analysis |
| `keyspace` | `context.cassandra.keyspace` | Must-exist for table-level metrics |
| `columnfamily` / `table` | `context.cassandra.columnfamily` | Must-exist for table-level metrics |
| `datacenter` | `context.cassandra.datacenter` | Must-exist for multi-DC setups; Unknown for single-DC |
| `operation` | `context.cassandra.operation` | Must-exist for request type filtering |
| `pool.name` | `context.cassandra.thread_pool` | Must-exist for thread pool metrics |
| `cache_result` | `context.cassandra.cache_result` | Must-exist for cache hit/miss metrics |
| `percentile` | `context.cassandra.percentile` | Must-exist for pre-computed latency percentile metrics |
| `status` | `context.cassandra.status` | Must-exist for error count metrics |
| `gc.action` | `context.jvm.gc.action` | Optional (JVM target only) |
| `gc.cause` | `context.jvm.gc.cause` | Optional |

---

## Golden signals

### Traffic

**What it means for Cassandra:** Client request rate split by operation type (read, write, range_slice, cas_read, cas_write, view_write). Separate read and write rates because Cassandra workloads are designed around one or the other; the ratio is a tuning signal and an anomaly indicator.

**Confirmed:** `cassandra.client.request.count` with `operation` attribute provides exact client request counts per operation type. [OTel java-contrib Cassandra metrics]

**Best-practice inference:** Table-level `cassandra.table.operation.count` gives finer breakdown when a specific keyspace/table is suspect, but MUST NOT be summed across hosts for cluster-wide throughput (double-counts due to replication).

**Typical causes of degradation:** Sudden traffic spike from application code change; batch jobs triggering range scans; node failure redistributing load to survivors.

**What people page on:** Read or write rate drops to near-zero (node unreachable or application-side issue); rate exceeds 3x baseline with concurrent latency increase.

**Section questions:** "Is the cluster handling the expected read/write request load?" | "Which keyspaces and tables are generating the most traffic?"

### Errors

**What it means for Cassandra:** `cassandra.client.request.error.count` counts timeouts and unavailables from the client's perspective. Dropped messages (`cassandra.thread_pool.dropped_tasks`) are a distinct and more critical signal — they indicate the node discarded work rather than completing it.

**Confirmed:** Both metrics exist in OTel JMX Cassandra target. [OTel java-contrib]

**Best-practice inference:** Dropped messages > 0 is essentially a pager condition. `client.request.error.count` can be non-zero normally under high CAS write contention — distinguish by checking operation type.

**Typical causes:** Write timeout = coordinator couldn't get enough replicas to acknowledge; Read timeout = replicas too slow; Dropped = thread pool backlog exceeded timeout.

**What people page on:** Any sustained dropped messages (even 1/s is alarming); read/write error rate above ~1%.

**Section questions:** "Are client requests failing or timing out?" | "Are any messages being dropped (node overload signal)?"

### Latency

**What it means for Cassandra:** Cassandra latency is a composite of coordinator routing time, SSTable reads (disk I/O), bloom filter checks, key cache lookups, compaction interference, and JVM GC pauses. p99 is the primary SLA signal; p50 gives typical performance.

**Confirmed:** `cassandra.client.request.read.latency.99p` and `.write.latency.99p` are pre-computed percentile gauges from JMX. They are NOT histograms — use `average` aggregation + no post-function. [OTel java-contrib]

**Best-practice inference:** Read latency in Cassandra is typically higher variance than write latency because reads must touch disk (SSTables), while writes hit Memtable first. A p99 read latency spike almost always points to one of: compaction backlog, GC pause, tombstone accumulation, or hot partition.

**What people page on:** p99 read latency exceeding SLA (typically 10–50ms depending on application); write p99 > 5ms; any latency step-change (sudden increase, not gradual drift).

**Section questions:** "Are reads completing within SLA?" | "Are writes completing within SLA?" | "Which tables or nodes are contributing to tail latency?"

### Saturation

**What it means for Cassandra:** Multiple saturation surfaces exist: thread pool pending tasks (leading indicator for drops), heap utilization (GC pressure), compaction backlog (read amplification), disk usage per node. Compaction pending is the most Cassandra-specific saturation signal — it has a direct, causal link to read latency.

**Confirmed:** `cassandra.compaction.tasks.pending`, `cassandra.thread_pool.pending_tasks`, `jvm.memory.heap` are all in the OTel JMX target.

**Best-practice inference:** Heap > 70% with active GC is more urgent than disk at 80%. Disk at 95%+ causes Cassandra to stop accepting writes (write-ahead log full); monitor storage load per node.

**What people page on:** Compaction pending > 50 per node growing trend; heap > 75% with frequent major GC; ReadStage or MutationStage pending tasks > 100.

**Section questions:** "Is the compaction backlog growing?" | "Is heap/GC pressure causing stalls?" | "Are thread pools backing up?"

---

## Telemetry sources

**Confirmed by sources:**
- OTel JMX receiver Cassandra target: https://github.com/open-telemetry/opentelemetry-java-contrib/blob/main/jmx-metrics/docs/target-systems/cassandra.md
- OTel JMX receiver JVM target: https://github.com/open-telemetry/opentelemetry-java-contrib/blob/main/jmx-metrics/docs/target-systems/jvm.md

**Best-practice inference:** In Kubernetes, use the OTel JMX receiver as a sidecar with Cassandra JMX port (7199 default) exposed on the pod. Enable both `cassandra` and `jvm` targets in the same receiver config.

| Source type | How collected | What it provides | Pros | Cons | Common pitfalls |
|---|---|---|---|---|---|
| OTel JMX Receiver (`cassandra` target) | OTel Collector with `jmxreceiver`, `cassandra` target | Full JMX client request metrics, thread pools, compaction, table-level, storage | Open-source; full coverage; semantic conventions aligned | Requires JMX port (7199) accessible; JMX must not require auth or SSL must be configured | JMX port blocked by K8s NetworkPolicy; receiver silent fail if JMX unreachable |
| OTel JMX Receiver (`jvm` target) | Same OTel Collector, `jvm` target for the Cassandra JVM process | Heap used/max, GC count, GC elapsed time | Standard JVM observability | Must target the correct JVM process (Cassandra's PID) | Missing if only `cassandra` target is configured; heap metrics won't appear |
| Prometheus JMX Exporter (alternative) | `jmx_prometheus_javaagent` loaded as JVM agent | Same JMX metrics in Prometheus format | Battle-tested; no OTel required | Metric naming differs (`cassandra_clientrequest_latency_micros_count` vs OTel names); translation required for Tsuga | Name mismatch causes Stage 2 prefix discovery to fail if wrong names used |
| Cassandra Nodetool checks | `nodetool status` via shell | Node UP/DOWN state, token ownership, replication availability | Ground truth for cluster membership | Not suitable for high-frequency polling; not a standard metric stream | Adds operational overhead; separate integration from JMX metrics |

**"No data" meanings:**
- `cassandra.*` metrics absent: OTel JMX receiver not running, JMX connection refused, or wrong `targetSystem` config
- `jvm.*` metrics absent: `jvm` target not added to `targetSystems` list in jmxreceiver config
- Metrics present but `operation` attribute missing: older version of OTel java-contrib jmx-metrics gatherer
- `cassandra.table.*` metrics absent: can happen when no keyspace/table traffic exists or Cassandra version differences

---

## Log intelligence (Stage 4 handoff)

### Confirmed by sources

**Log sources matrix:**

| Source | Access path | Typical format | Structured vs unstructured | Evidence |
|---|---|---|---|---|
| System log (`system.log`) | `/var/log/cassandra/system.log` on host; stdout/stderr in K8s | Custom Cassandra multi-field format | Unstructured | [Cassandra logging docs](https://cassandra.apache.org/doc/latest/cassandra/operating/logging.html) |
| Debug log (`debug.log`) | `/var/log/cassandra/debug.log` | Same format, more verbose | Unstructured | Cassandra logging docs |
| GC log | JVM `-Xloggc:/path/to/gc.log` flag | JVM GC log format (G1GC or CMS) | Semi-structured | JVM standard |
| Audit log (optional) | Configurable path; requires `audit_logging_options.enabled: true` in cassandra.yaml | Cassandra audit format or BIN format | Optional/structured | [Cassandra audit logging](https://cassandra.apache.org/doc/latest/cassandra/operating/audit_logging.html) |

**Known log formats:**

Format: Cassandra `system.log` default format
```
INFO  [main] 2024-01-15 10:23:45,678 StorageService.java:1234 - Node localhost/127.0.0.1 state jump to NORMAL
WARN  [ReadStage-1] 2024-01-15 10:23:46,123 Keyspace.java:567 - Read 100 live rows and 500 tombstone cells for query SELECT * FROM my_keyspace.my_table; (TombstoneWarning)
ERROR [MutationStage-2] 2024-01-15 10:23:47,234 CassandraDaemon.java:890 - Exception in thread
```

Field structure:
- Position 1: Level (INFO/WARN/ERROR/DEBUG)
- Position 2: `[ThreadName-N]` — thread pool and worker index
- Position 3–4: Timestamp `YYYY-MM-DD HH:mm:ss,SSS` (comma subsecond separator, not dot)
- Position 5: `ClassName.java:lineNumber`
- Position 6: ` - ` separator
- Position 7+: Free-text message body

**Candidate query filters for Stage 4:**
1. **Precise:** `service.name:cassandra` or `source:cassandra` — preferred if log collector tags correctly; use if Filebeat/Fluentd/OTel sets service name
2. **Broader fallback:** filter on known thread names: `"StorageService" OR "MutationStage" OR "ReadStage" OR "CompactionExecutor"` — works without proper service tagging; risk = false positives from any Java app with similar thread names

**Attribute mapping hints:**

| Raw field | Suggested Tsuga key | Confidence | Notes |
|---|---|---|---|
| Log level (INFO/WARN/ERROR) | `level` | High | Standard log level |
| Thread name (e.g., ReadStage-1) | `cassandra.thread` | Medium | Contains thread pool identity useful for correlating with metrics |
| Timestamp | `timestamp` | High | Standard; note comma subsecond separator requires custom grok |
| Source class (ClassName.java:line) | `cassandra.source_class` | Medium | Useful for filtering specific Cassandra internals |
| Message body | `message` | High | Free text; further Grok parsing for specific warnings |
| Keyspace (from tombstone/query warnings) | `cassandra.keyspace` | Medium | Parseable from "SELECT * FROM keyspace.table" message patterns |
| Table name | `cassandra.table` | Medium | Same parsing as keyspace |
| Tombstone count (from WARN messages) | `cassandra.tombstones_scanned` | Low | Only present in tombstone warning log lines |
| Node address (from StorageService logs) | `cassandra.node` | Medium | IP or hostname extracted from "Node ip/host state jump to..." |

### Best-practice inference

**Parsing risks:**
- **Multiline stack traces:** Lines starting with whitespace or `\tat` are continuation lines of a previous ERROR/WARN. Requires regex multiline continuation pattern.
- **Thread name variability:** Thread names contain pool type + hyphen + number (e.g., `ReadStage-3`); the number changes with thread pool size.
- **Embedded CQL queries:** Tombstone warning messages contain embedded CQL SELECT queries that may span long lines with column lists, keyspace.table names, and WHERE clauses.
- **Comma in timestamp:** The subsecond separator is `,` not `.` — standard strptime patterns will fail; needs custom grok `%{NUMBER:subsecond}` or character class match.
- **Audit log format difference:** If audit logging is enabled, a second log source with different format will appear; must split-route or differentiate by filename.
- **GC log format entirely different:** JVM GC logs use their own format and must be parsed with GC-specific patterns.

---

## Caveats and footguns

- **[read-latency, write-latency]** `cassandra.client.request.read.latency.*` and all JMX latency metrics are **pre-computed percentile gauges**, NOT histograms. Use `average` aggregation + `none` post-function. Using `sum` or rate post-functions produces meaningless numbers. (Confirmed, OTel java-contrib source)
- **[throughput]** `cassandra.client.request.count` is a **cumulative counter**. Use `rate` post-function for bucketed (timeseries) widgets to show requests/second. Displaying the raw value gives an ever-increasing line with no operational meaning. (Confirmed)
- **[throughput, read-latency]** `cassandra.table.operation.count` **double-counts** at cluster level: the coordinator counts a request, and each replica also counts its local operation. Never sum `table.operation.count` across all hosts for cluster-wide throughput — use `cassandra.client.request.count` instead. (Confirmed, Datadog guide)
- **[compaction]** `cassandra.compaction.tasks.pending` being **non-zero is normal**. Cassandra always has background compaction work. Only a steadily growing trend above 10–20 is a problem. A widget showing "5 pending" looks alarming but is healthy. (Confirmed, Cassandra docs)
- **[cache-efficiency]** Row cache (`cassandra.table.cache.hit` metrics) is **disabled by default**. Absence of row cache metrics is expected, not an error. Only enable row cache for narrow, frequently-read hot rows — large rows make it counterproductive. (Confirmed)
- **[cache-efficiency]** `cassandra.table.bloom_filter.false_ratio` near **0 is GOOD, near 1 is BAD**. This is an error rate, not a hit rate. A widget using default "more = better" coloring will mislead. Invert your mental model. (Confirmed)
- **[memory-gc]** `jvm.memory.heap` (heap used) **without knowing max heap** gives no utilization context. Raw bytes alone is not actionable for on-call. Always pair with `jvm.memory.heap.max` in a utilization ratio derived signal. (Best-practice inference)
- **[memory-gc]** Read latency p99 spikes are frequently caused by **JVM stop-the-world GC pauses**, not slow disk. Always correlate latency spikes with GC pause duration before assuming a disk or compaction issue. (Confirmed, Cassandra performance docs)
- **[throughput]** CAS (LWT) operations (`operation:cas_read`, `operation:cas_write`) are **significantly more expensive** than normal operations and inflate latency averages if mixed with regular reads/writes. Separate CAS metrics; do not include them in general throughput averages. (Confirmed)
- **[thread-pools]** Thread pool names vary by Cassandra version. Key pools: `ReadStage`, `MutationStage`, `CompactionExecutor`, `MemtableFlushWriter`, `GossipStage`, `AntiEntropyStage`. If `pool.name` attribute is missing, thread pool metrics are unsliced and cannot be triaged by pool. Stage 2 must verify exact attribute values. (Confirmed, Cassandra threading model)
- **[errors-dropped]** `cassandra.thread_pool.dropped_tasks` is a **cumulative counter**. A non-zero value means drops have occurred since startup, not that they are happening now. Use `rate` to see current drop rate; `increase` to see drops in a time window. (Confirmed)
- **[compaction]** `cassandra.compaction.tasks.completed` is cumulative — use `rate` for "completions per second". Displaying raw value gives an ever-increasing, meaningless line. (Confirmed)
- **[read-latency]** `cassandra.table.tombstone_scanned` p95 > 100 is a **warning sign**. Cassandra's default `tombstone_warn_threshold` is 1,000 and `tombstone_failure_threshold` is 100,000 (set in cassandra.yaml, not surfaced as metrics). These are per-query limits. (Confirmed, cassandra.yaml docs)
- **[storage-hints]** `cassandra.storage.total_hints.count` is a cumulative counter of hints dispatched — **not the current backlog**. Use `cassandra.storage.total_hints.in_progress.count` (gauge) as the real-time measure of pending hint delivery. If in-progress is growing while a node is down, data durability is at risk. (Confirmed)
- **[read-latency, write-latency]** JMX metrics are **sampled at the JMX scrape interval** (not every operation). High-throughput clusters may show slightly smoothed latency values. Percentiles are still directionally accurate but may miss very brief spikes narrower than the scrape interval. (Best-practice inference)
- **[cache-efficiency]** Key cache size is bounded by `key_cache_size_in_mb` in cassandra.yaml. If the key cache is full, hit rate plateaus even on warm workloads — this is expected, not a fault. Increasing key_cache_size_in_mb can improve it. (Confirmed)
- **[compaction]** TWCS (TimeWindowCompactionStrategy) tables generate **large pending compaction counts at window boundaries** — this is expected behavior for time-series workloads and not indicative of a problem. Threshold alerting on compaction pending is dangerous for TWCS tables. (Confirmed, TWCS docs)
- **[cluster-health]** Cassandra node "DOWN" in gossip **does not immediately mean data is unavailable**. With RF=3 and CL=QUORUM, two remaining nodes still serve reads and writes. Availability depends on CL + RF, not raw node count. (Confirmed)
- **[storage-hints]** `cassandra.storage.load.count` reports **data WITHOUT snapshot content** on some Cassandra versions (as labeled in Datadog reference dashboard). Do not compare directly to `df` output — it is Cassandra's internal accounting of live data size. (Confirmed, reference dashboard)
- **[read-latency, write-latency]** `cassandra.table.operation.latency` uses a `percentile` attribute with values `50p`, `99p`, and `max` (confirm in Stage 2). Always filter to specific percentile when using this metric — grouping by percentile produces nonsensical aggregated series. (Confirmed OTel, attribute values INFERRED)
- **[throughput]** `cassandra.table.coordinator.read` and `cassandra.table.coordinator.scan` are per-keyspace/table. Grouping across keyspaces without a Top-N limit can produce cardinality explosion if many tables exist. Always apply `top_n`. (Best-practice inference)
- **[compaction]** `cassandra.table.bloom_filter.false_ratio` increases when SSTables are old and not yet compacted. It resets to near-zero after compaction completes for a table. A rising bloom filter false ratio is a leading indicator that compaction is falling behind for that table. (Confirmed)

---

## Confirmed Tsuga prefixes

- `cassandra.*` — **CONFIRMED** (Stage 2: 16 metrics discovered; cassandra.client.*, cassandra.compaction.*, cassandra.storage.* present; cassandra.table.* and cassandra.thread_pool.* absent — require OTel collector config update)
- `jvm.*` — **CONFIRMED** (Stage 2: 28 JVM metrics discovered; includes jvm.memory.heap.*, jvm.gc.collections.*, jvm.gc.duration, jvm.cpu.*, jvm.thread.count, jvm.class.*)

**Stage 2 key corrections applied:**
- Attribute for operation type: `context.operation` (NOT `context.cassandra.operation`)
- Attribute for error status: `context.status` (NOT `context.cassandra.status`)
- Per-node dimension for cassandra.* metrics: `context.service.name` (no `context.host` on these metrics)
- Per-node dimension for jvm.* metrics: `context.host.name`
- Range latency metric name: `cassandra.client.request.range_slice.latency.*` (NOT `range.latency`)
- Max latency variants confirmed present for read, write, and range_slice

---

## Discovery status

Discovery: not yet performed (deferred to Stage 2)

---

## Top sources

1. https://github.com/open-telemetry/opentelemetry-java-contrib/blob/main/jmx-metrics/docs/target-systems/cassandra.md — canonical OTel JMX metric names, attribute names, types, and units for Cassandra
2. https://cassandra.apache.org/doc/latest/cassandra/operating/metrics.html — official Cassandra JMX MBean metrics reference (maps JMX to semantic names)
3. https://www.datadoghq.com/blog/how-to-monitor-cassandra-performance-metrics/ — golden signal selection, threshold guidance, and metric interpretation for on-call use
4. https://cassandra.apache.org/doc/latest/cassandra/operating/compaction/ — compaction strategies, tuning options, and operational monitoring for STCS/LCS/TWCS
5. https://www.datadoghq.com/blog/tlp-cassandra-dashboards/ — dashboard design rationale and curated metric selection from Cassandra experts
6. https://cassandra.apache.org/doc/latest/cassandra/operating/logging.html — log format, log levels, file locations, and runtime configuration
7. https://cassandra.apache.org/doc/latest/cassandra/configuration/cass_yaml_file.html — cassandra.yaml reference (tombstone thresholds, cache sizes, GC tuning, hint TTL)
8. https://github.com/open-telemetry/opentelemetry-java-contrib/blob/main/jmx-metrics/docs/target-systems/jvm.md — OTel JMX JVM target metrics (heap, GC count, GC elapsed)
9. https://cassandra.apache.org/doc/latest/cassandra/operating/hints.html — hinted handoff mechanism, hint TTL, monitoring hint accumulation and replay
10. https://cassandra.apache.org/doc/latest/cassandra/operating/read_repair.html — read repair mechanics, consistency implications, and latency overhead
