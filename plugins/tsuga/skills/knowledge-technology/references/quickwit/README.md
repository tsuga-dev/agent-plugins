# Quickwit Integration Context Bundle

**Technology:** Quickwit
**Deployment:** AWS cloud (self-hosted)
**Environment:** prod
**Persona:** SRE Dev and ops
**Telemetry preference:** mixed
**Integration scope:** core service only
**Primary use-case:** reliability and performance

## How to use this bundle

- **07** (`07_quickwit_dashboard_plan.yaml`) — Dashboard structure, widget specs, section definitions. Start here for building.
- **05** (`05_quickwit_metric_inventory.csv`) — Source of truth for all metrics: names, types, units, aggregations, group-bys.
- **09** (`09_quickwit_section_notes_and_playbooks.md`) — All note content, triage chains, and operational playbooks.

## Confirmed Tsuga prefixes

- `quickwit_*` — **CONFIRMED** (31/31 inventory metrics present in Tsuga; 0 missing. 92 additional metrics discovered beyond inventory scope. Naming uses underscore convention, e.g. `quickwit_indexing_processed_bytes`)
- `quickwit_quickwit_janitor_*` — **CONFIRMED** (4 metrics; janitor metrics have doubled prefix `quickwit_quickwit_janitor_*`)
- `prometheus_quickwit_*` — **CONFIRMED** (123 duplicate metrics with `prometheus_` prefix; not used in dashboards)

## Discovery status

Discovery: **COMPLETED** (2026-02-10)

- **Metrics found:** 246 total (123 `quickwit_*` + 123 `prometheus_quickwit_*` duplicates)
- **All 31 inventory metrics confirmed** (0 missing)
- **92 unexpected metrics** discovered (cluster, control plane, runtime, additional search/storage/ingest metrics)
- **Counter temporality:** ALL delta → `per-second` is the correct post-function
- **Context fields reconciled:** `context.scope.name` → `context.service.name`, `context.operation` → `context.rpc`, `context.cache` → `context.component_name`, `context.error` → `context.status`
- **All 7 Stage 1 unknowns resolved**

## Bundle files

| # | Filename | Purpose |
|---|---|---|
| 00 | `00_quickwit_cover.md` | This file. Bundle metadata, prefixes, sources, navigation. |
| 01 | `01_quickwit_executive_overview.md` | What it is, what "good" looks like, top incident shapes. |
| 02 | `02_quickwit_key_concepts.md` | Glossary, concept map, entities/dimensions, Tsuga field mapping. |
| 03 | `03_quickwit_golden_signals.md` | Traffic/Errors/Latency/Saturation mapped to Quickwit. |
| 04 | `04_quickwit_telemetry_sources.md` | Source matrix, optional features, "no data" interpretation. |
| 05 | `05_quickwit_metric_inventory.csv` | All metrics: names, types, units, Tsuga mapping, widget specs. |
| 06 | `06_quickwit_derived_signals.csv` | 13 derived KPIs: formulas, inputs, gating, interpretation. |
| 07 | `07_quickwit_dashboard_plan.yaml` | 7 sections, 2 dashboards (overview + deep dive), full widget specs. |
| 09 | `09_quickwit_section_notes_and_playbooks.md` | Mission note, section notes, 21 triage chains, 7 playbooks. |
| 10 | `10_quickwit_caveats_footguns.md` | 20+ caveats tagged by section: cardinality, misleading metrics, unit traps. |
| 11 | `11_quickwit_unknowns_verify_next.yaml` | Unknowns tracking (all 7 Stage 1 unknowns resolved by discovery). |
| 12 | `12_quickwit_discovery_reconciliation.md` | Stage 2 discovery & reconciliation report. |

## Top sources

1. [Quickwit Architecture](https://quickwit.io/docs/overview/architecture) — Core architecture: 5 service roles, Chitchat, S3 storage model
2. [Quickwit Cluster Sizing](https://quickwit.io/docs/main-branch/deployment/cluster-sizing) — Resource requirements, throughput benchmarks (7.5 MB/s/core)
3. [Quickwit Index Configuration](https://quickwit.io/docs/configuration/index-config) — Merge policy, commit timeout, retention, heap size
4. [Quickwit Grafana Dashboards (GitHub)](https://github.com/quickwit-oss/quickwit/tree/main/monitoring/grafana/dashboards) — Official Grafana dashboards referencing all key metrics
5. [Quickwit Metrics Reference](https://quickwit.io/docs/reference/metrics) — Official metrics documentation
6. [Quickwit common/metrics.rs (GitHub)](https://github.com/quickwit-oss/quickwit/blob/main/quickwit/quickwit-common/src/metrics.rs) — Memory metrics, in-flight data, metric framework
7. [Quickwit janitor/metrics.rs (GitHub)](https://github.com/quickwit-oss/quickwit/blob/main/quickwit/quickwit-janitor/src/metrics.rs) — GC metrics definitions
8. [Quickwit 0.8 Blog](https://quickwit.io/blog/quickwit-0.8) — Ingest v2, shard-based ingestion, petabyte-scale benchmarks
9. [Quickwit WAL Metrics Issue #5547](https://github.com/quickwit-oss/quickwit/issues/5547) — WAL metrics only work with ingest v2
10. [Quickwit Search RAM Issue #5355](https://github.com/quickwit-oss/quickwit/issues/5355) — Search memory usage and OOM risk


---

# Quickwit Executive Overview

## What it is
Quickwit is a cloud-native search engine built in Rust, designed for log management and distributed tracing on object storage (S3). It decouples compute from storage, enabling petabyte-scale search at a fraction of the cost of Elasticsearch. In a typical stack, Quickwit serves as the log and trace search/analytics backend, receiving data via OTLP gRPC, Kafka, or its REST ingest API, indexing it into splits stored on S3, and serving search queries over those splits.

## Where it runs
Self-hosted on Kubernetes (AWS). Five service roles: **Indexer** (builds indexes from ingested data), **Searcher** (executes queries), **Control Plane** (coordinates indexing workloads), **Metastore** (stores index metadata in PostgreSQL), and **Janitor** (GC and retention). Nodes communicate via a Chitchat gossip protocol for cluster membership.

## What "good" looks like
- Indexers processing data at expected throughput (7.5 MB/s/core) with low backpressure and no merge backlogs
- Searchers responding to queries within SLO latency, with high cache hit ratios and bounded memory
- Ingest gRPC requests succeeding with low error rate and stable request duration
- Metastore gRPC calls fast (<100ms p95) with near-zero errors
- Object storage request rates stable, WAL disk/memory usage well within configured limits
- All cluster nodes visible and healthy; no split GC failures

## Top 3 incident shapes

| Incident | First dashboard section |
|---|---|
| **Ingest pipeline stall** — indexing throughput drops, backpressure spikes, WAL fills up | Indexing & Throughput |
| **Search latency spike** — leaf searches slow, cache misses increase, S3 GET latency rises | Search Performance |
| **Cluster split-brain / node loss** — metastore errors spike, indexing stops, control plane cannot schedule | Cluster Health & gRPC |

---

### Confirmed by sources
- Architecture (5 services, Chitchat, S3 storage): [Quickwit Architecture](https://quickwit.io/docs/overview/architecture)
- Indexing throughput benchmark (7.5 MB/s/core): [Cluster Sizing](https://quickwit.io/docs/main-branch/deployment/cluster-sizing)
- Petabyte-scale production use (1 PB/day, 40 PB stored): [Quickwit 0.8 blog](https://quickwit.io/blog/quickwit-0.8)

### Best-practice inference
- "Good" latency targets (<100ms p95 metastore) are inferred from operational best practices, not documented SLOs.
- Incident shapes are inferred from architecture analysis and community issue patterns (GitHub issues #5547, #5355, #668).


---

# Quickwit Key Concepts

## Glossary (>= 20 terms)

| Term | Definition | Operational meaning | Dashboard section affected |
|---|---|---|---|
| **Index** | A logical collection of documents with a schema (doc mapping). Analogous to an ES index. | Each index has its own indexing pipeline(s) and search scope. | All sections (filter by index) |
| **Split** | An immutable chunk of indexed data (tantivy segment bundle) stored as a single object in S3. Target: 10M docs per split. | Splits are the unit of storage, search, merge, and GC. Too many small splits = slow search; too few large = slow merge. | Indexing, Search, Storage |
| **Shard** | A write-ahead partition within the ingest pipeline (ingest v2). Each shard is assigned to one indexer. | Shard count and state (open/closed) indicate ingest pipeline health. | Ingest Health |
| **WAL (Write-Ahead Log)** | Durable buffer for ingested data before indexing. Stored on local disk + memory. | WAL fill level indicates backpressure. If WAL is full, ingest rejects writes. | Ingest Health |
| **Indexer** | Service role that consumes data from sources, builds indexes (splits), and uploads them to object storage. | CPU and memory intensive. Throughput is the primary KPI. | Indexing & Throughput |
| **Searcher** | Stateless service role that executes search queries by downloading split data from S3. | Memory intensive (needs RAM for split data). Cache hit ratio is critical. | Search Performance |
| **Control Plane** | Service role that schedules and distributes indexing workloads across indexers. | Single point of coordination. Failure stalls new index assignments. | Cluster Health |
| **Metastore** | Service role that stores index metadata. Backed by PostgreSQL or file-based storage. | gRPC latency and error rate directly impact all operations. | Metastore Performance |
| **Janitor** | Service role that runs periodic maintenance: garbage collection of orphan splits, retention enforcement. | GC failures cause storage bloat. | Storage & GC |
| **Merge** | Background process that combines small splits into larger ones to optimize search performance. | Merge backlog indicates indexer overload. Ongoing + pending merge ops are key gauges. | Indexing & Throughput |
| **Backpressure** | Signal that the indexing pipeline is overwhelmed. Measured in microseconds of wait time. | Sustained backpressure = data ingestion is being throttled. | Indexing & Throughput |
| **Leaf search** | The portion of a search query executed on individual splits by a searcher node. | Leaf search split count indicates query fan-out and cost. | Search Performance |
| **Root search** | The coordinator portion of a search query that fans out leaf searches and merges results. | High root search latency with low leaf latency = merge overhead or network. | Search Performance |
| **Split footer cache (hotcache)** | In-memory cache of split metadata (footer bytes). Default: 500MB. | Cache misses = extra S3 GETs per query. | Search Performance, Cache |
| **Fast field cache** | In-memory cache for columnar data used in aggregations. Default: 1GB. | Evictions degrade aggregation latency. | Search Performance, Cache |
| **Commit timeout** | Max seconds before an indexer commits a split (default: 60s). | Lower = fresher data but more small splits; higher = larger splits but higher ingest latency. | Indexing & Throughput |
| **Merge policy** | Strategy for combining splits. Default: stable_log (merge factor 10). | Wrong policy = merge backlog or too many splits. | Indexing & Throughput |
| **Retention policy** | Automatic deletion of splits older than a configured period. | Janitor enforces retention. Missing GC runs = unbounded storage growth. | Storage & GC |
| **Chitchat** | Gossip-based cluster membership protocol used by Quickwit nodes. | Cluster membership changes affect routing and scheduling. | Cluster Health |
| **Source** | Data ingestion source configuration: ingest API, Kafka, Kinesis, Pulsar, file. | Source type determines how data enters the indexing pipeline. | Ingest Health |
| **Object storage** | S3 (or compatible) backend where splits are stored. | GET/PUT rates and transfer bytes are primary storage KPIs. | Storage & Object Store |
| **In-flight data** | Bytes currently being processed in the indexing pipeline, tracked per component. | High in-flight data with low throughput = pipeline stall. | Memory & Resources |
| **Doc processor** | Pipeline stage that parses, validates, and transforms documents before indexing. | Mailbox backlog indicates processing bottleneck. | Indexing & Throughput |

## Concept map (>= 25 lines)

```
Client -> sends data to -> Ingest API / Kafka Source (entry point for data)
Ingest API -> writes to -> WAL (durability before indexing)
WAL -> feeds -> Shard (partitioned write buffer)
Control Plane -> assigns -> Shard to Indexer (workload scheduling)
Shard -> consumed by -> Indexer (data processing)
Indexer -> builds -> Split (immutable indexed chunk)
Indexer -> runs -> Doc Processor (parse + validate)
Indexer -> runs -> Merge (combine small splits)
Indexer -> uploads to -> Object Storage / S3 (persistent storage)
Indexer -> reports to -> Metastore (split metadata registration)
Indexer -> experiences -> Backpressure (when pipeline overloaded)
Merge -> combines -> Splits (optimization for search)
Merge -> uploads to -> Object Storage / S3 (merged split)
Merge -> updates -> Metastore (merged split metadata)
Searcher -> receives -> Search Query (from client)
Searcher -> performs -> Root Search (query coordination)
Root Search -> fans out to -> Leaf Search (per-split execution)
Leaf Search -> downloads from -> Object Storage / S3 (split data)
Leaf Search -> uses -> Split Footer Cache (metadata cache, avoids S3 GETs)
Leaf Search -> uses -> Fast Field Cache (columnar data cache)
Searcher -> returns -> Results to Client
Metastore -> backed by -> PostgreSQL (metadata durability)
Metastore -> serves -> gRPC API (used by all services)
Janitor -> performs -> Garbage Collection (orphan split deletion)
Janitor -> enforces -> Retention Policy (age-based split deletion)
Janitor -> deletes from -> Object Storage / S3 (split cleanup)
Chitchat -> manages -> Cluster Membership (node discovery)
Control Plane -> monitors -> Indexer Health (scheduling decisions)
Control Plane -> queries -> Metastore (index/source metadata)
```

## Entities and dimensions (>= 12)

| Entity/Dimension | Why useful | Cardinality risk | Safe top-N | Do NOT group-by |
|---|---|---|---|---|
| **instance/pod** | Per-node breakdown for hotspot detection | Medium (10-200 pods) | 10 | - |
| **index** | Per-index throughput and performance | Low-Medium (1-100 indexes) | 10 | - |
| **source** | Ingest source breakdown (kafka, ingest-api, etc.) | Low (1-5) | 5 | - |
| **operation** (gRPC) | gRPC method breakdown for metastore/ingest | Low-Medium (10-30) | 10 | - |
| **component** (in-flight) | Pipeline component breakdown (rest_server, wal, indexer, etc.) | Low (10-15) | 15 | - |
| **shard state** | Open vs closed shards | Very low (2) | 2 | - |
| **cache name** | Cache type (fastfields, shortlived, splitfooter) | Very low (3) | 3 | - |
| **k8s cluster** | Cross-cluster comparison | Low | 10 | - |
| **k8s namespace** | Namespace-level breakdown | Low-Medium | 10 | - |
| **k8s pod name** | Per-pod granularity | Medium-High | 10 | Group-by with caution; prefer instance |
| **cloud region** | Regional breakdown | Very low (1-5) | 5 | - |
| **error (boolean)** | Success vs failure on gRPC | Very low (2) | 2 | - |
| **service role** | Indexer/Searcher/Control Plane/Metastore/Janitor | Very low (5) | 5 | - |

## Tsuga field mapping table

| Vendor/exporter dimension | Recommended context.* key | Must-exist? | Notes |
|---|---|---|---|
| `instance` / `pod` | `context.scope.name` | Must-exist | Primary instance identifier |
| `index` | `context.index` | Optional | Per-index breakdown; Unknown if available in Tsuga |
| `source_type` | `context.source` | Optional | Unknown if available in Tsuga |
| `operation` | `context.operation` | Optional | gRPC method name |
| `component` | `context.component` | Optional | In-flight data component label |
| `state` | `context.state` | Optional | Shard state (open/closed) |
| `cache` | `context.cache` | Optional | Cache name label |
| `k8s cluster` | `context.k8s.cluster.name` | Optional | K8s cluster name |
| `k8s namespace` | `context.k8s.namespace.name` | Optional | K8s namespace |
| `k8s pod` | `context.k8s.pod.name` | Optional | K8s pod name |
| `env` | `context.env` | Must-exist | Environment tag |
| `team` | `context.team` | Must-exist | Team ownership tag |
| `region` | `context.cloud.region` | Optional | AWS region |
| `error` | `context.error` | Optional | Error boolean on gRPC histograms |

---

### Confirmed by sources
- Architecture roles (Indexer, Searcher, Control Plane, Metastore, Janitor): [Architecture](https://quickwit.io/docs/overview/architecture)
- Split, Index, Merge concepts: [Quickwit 101](https://quickwit.io/blog/quickwit-101)
- Shard and WAL (ingest v2): [Quickwit 0.8](https://quickwit.io/blog/quickwit-0.8)
- Commit timeout, merge policy, retention: [Index Configuration](https://quickwit.io/docs/configuration/index-config)
- Cache types (splitfooter, fastfields): [Metrics Reference](https://quickwit.io/docs/reference/metrics)
- Cluster sizing (7.5 MB/s/core, 8GB RAM/core searcher): [Cluster Sizing](https://quickwit.io/docs/main-branch/deployment/cluster-sizing)
- Chitchat gossip protocol: [Architecture](https://quickwit.io/docs/overview/architecture)

### Best-practice inference
- Tsuga context.* field mappings are inferred; actual field names in Tsuga depend on how the OTel Collector or Prometheus scraper maps labels. Stage 2 discovery will confirm.
- "Do NOT group-by" guidance on k8s pod name is best-practice (high cardinality in large clusters).


---

# Quickwit Golden Signals

## Traffic

**What it means for Quickwit:** Volume of data being ingested (bytes/s, docs/s) and volume of search queries being served (leaf searches, gRPC requests). Quickwit has two distinct traffic planes: write (ingest) and read (search).

**Typical causes when it degrades:**
- Upstream source stops sending data (Kafka consumer lag, ingest API client failure)
- Control plane cannot schedule indexing pipelines (metastore unreachable)
- Search traffic drops because clients receive errors and stop retrying

**Best telemetry sources:**
- `quickwit_indexing_processed_bytes` (indexing throughput)
- `quickwit_indexing_processed_docs_total` (document throughput)
- `quickwit_ingest_grpc_requests_total` (ingest gRPC request rate)
- `quickwit_search_leaf_searches_splits_total` (search fan-out volume)

**What people page on:**
- Indexing throughput drops significantly below baseline for sustained period
- Ingest request rate drops to zero unexpectedly
- Search query volume anomaly (sudden drop or spike)

**Section questions:**
1. Is data flowing into the cluster at the expected rate?
2. Are search queries being served at normal volume?
3. How is ingest throughput distributed across indexes and sources?

---

## Errors

**What it means for Quickwit:** Failed gRPC requests to metastore or ingest services, indexing failures, GC failures, search errors. Quickwit surfaces errors primarily through gRPC error counters.

**Typical causes when it degrades:**
- Metastore (PostgreSQL) connectivity issues
- Object storage (S3) access failures (permissions, throttling, network)
- Indexer OOM kills (heap too small for workload)
- Schema validation failures on ingest

**Best telemetry sources:**
- `quickwit_ingest_grpc_requests_total` (filtered by error status)
- `quickwit_metastore_grpc_requests_total` (filtered by error status)
- `quickwit_janitor_gc_runs` (filtered by outcome)

**What people page on:**
- Ingest error rate exceeds baseline
- Metastore error rate spikes (all downstream operations affected)
- GC run failures (storage leak risk)

**Section questions:**
1. Are ingest and metastore gRPC calls succeeding?
2. Are there indexing pipeline failures?
3. Is garbage collection running successfully?

---

## Latency

**What it means for Quickwit:** Time to process ingest gRPC requests, metastore gRPC calls, and search queries. Search latency is dominated by S3 GET latency (split downloads). Ingest latency is dominated by WAL write + pipeline processing time.

**Typical causes when it degrades:**
- S3 latency spikes (regional issues, throttling)
- Cache misses forcing extra S3 round-trips
- Merge backlog causing too many small splits (more leaf searches per query)
- Metastore PostgreSQL slow queries
- Memory pressure causing GC pauses or swap

**Best telemetry sources:**
- `quickwit_ingest_grpc_request_duration_seconds` (ingest latency histogram)
- `quickwit_metastore_grpc_request_duration_seconds` (metastore latency histogram)
- `quickwit_indexing_backpressure_micros` (indexing pipeline backpressure)

**What people page on:**
- Ingest p95 latency sustained above SLO
- Metastore p95 latency exceeds normal baseline
- Indexing backpressure sustained above zero

**Section questions:**
1. Is ingest request latency within acceptable bounds?
2. Is metastore latency affecting downstream operations?
3. Is the indexing pipeline experiencing backpressure?

---

## Saturation

**What it means for Quickwit:** Resource exhaustion across the cluster: memory (RSS, in-flight data), disk (WAL usage), object storage (request rate limits), merge queue depth, shard capacity.

**Typical causes when it degrades:**
- Indexer heap exhausted (too many concurrent pipelines, large documents)
- Searcher memory exhausted (too many concurrent queries, large aggregations)
- WAL disk or memory limits reached (ingest v2)
- Merge operations backlogged (merge factor too aggressive, CPU starved)
- S3 request throttling (too many GETs/PUTs)

**Best telemetry sources:**
- `quickwit_memory_resident_bytes` / `quickwit_memory_allocated_bytes` (memory usage)
- `quickwit_memory_in_flight_data_bytes` (pipeline data pressure)
- `quickwit_ingest_wal_disk_used_bytes` / `quickwit_ingest_wal_memory_used_bytes` (WAL saturation)
- `quickwit_indexing_ongoing_merge_operations` / `quickwit_indexing_pending_merge_operations` (merge backlog)
- `quickwit_ingest_shards` (shard state counts)
- `quickwit_storage_object_storage_gets_total` / `quickwit_storage_object_storage_puts_total` (S3 request rates)

**What people page on:**
- Memory RSS approaching pod limits (OOMKill risk)
- WAL usage approaching configured max (ingest rejection risk)
- Merge pending operations growing unbounded
- S3 request rate approaching account limits

**Section questions:**
1. Is memory usage within safe bounds across indexers and searchers?
2. Is the WAL filling up, and are shards healthy?
3. Is the merge pipeline keeping up with indexing?
4. Are object storage operations within rate limits?

---

### Confirmed by sources
- Indexing throughput benchmarks and backpressure: [Cluster Sizing](https://quickwit.io/docs/main-branch/deployment/cluster-sizing)
- Search latency dominated by S3: [Lambda Search Performance](https://quickwit.io/blog/quickwit-lambda-search-performance)
- Merge policy and merge backlog: [Index Configuration](https://quickwit.io/docs/configuration/index-config)
- WAL metrics issues: [GitHub Issue #5547](https://github.com/quickwit-oss/quickwit/issues/5547)
- Memory pressure and search RAM cap: [GitHub Issue #5355](https://github.com/quickwit-oss/quickwit/issues/5355)
- OOM risk per search request (500MB default): [Cluster Sizing](https://quickwit.io/docs/main-branch/deployment/cluster-sizing)

### Best-practice inference
- Paging triggers (e.g., "sustained above SLO") are inferred; Quickwit does not publish official SLO targets.
- S3 throttling as a saturation signal is inferred from architecture (all data on S3).


---

# Quickwit Section Notes & Playbooks

---

## Part 1: Overview Mission Note

**Quickwit**
Cloud-native search engine for logs and traces on S3.
Prometheus scrape, all node roles.

[Quickwit Docs](https://quickwit.io/docs/) | [Architecture](https://quickwit.io/docs/overview/architecture) | [Deep Dive Dashboard](#)

---

## Part 2: Section Explanation Notes

### # Indexing & Throughput - Is data flowing into the cluster at the expected rate?

### So what?
**Healthy:** Indexing throughput tracks the expected ingest rate (benchmark: 7.5 MB/s per core). Backpressure near zero, pending merges stable.
**Concerning:** Throughput drops AND backpressure rises = pipeline is throttled. Pending merges growing unbounded = merge workers cannot keep up with split creation.
**Gotcha:** `processed_docs_total` increments in bursts at commit boundaries (default 60s). Short flat periods are normal, not a stall.

### Now what?
- Check which indexer pods show reduced throughput
- Look at backpressure per instance to find the bottleneck
- If merge backlog is growing, check CPU saturation on indexer nodes

---

### # Ingest Health - Are ingest pipelines accepting and processing data?

### So what?
**Healthy:** Ingest request rate matches expected client send rate, p95 latency under 500ms, near-zero errors, in-flight requests bounded.
**Concerning:** Error rate climbing = clients being rejected. p95 latency spiking = pipeline or metastore backpressure. WAL filling up = ingest will soon reject writes.
**Gotcha:** WAL and shard metrics only work with ingest v2. With ingest v1, these widgets show no data or misleading constants (GitHub #5547).

### Now what?
- Check ingest error rate and error type distribution
- Check WAL disk/memory usage against configured limits
- Verify metastore is responsive (metastore errors cascade into ingest failures)

---

### # Search Performance - Are queries fast and caches effective?

### So what?
**Healthy:** Cache hit ratio >95%, leaf search splits/s stable, cache size within configured capacity.
**Concerning:** Cache hit ratio dropping = cache pressure or new query patterns. Leaf splits/s spiking = queries scanning more splits (index growing, merge backlog creating many small splits).
**Gotcha:** Cache hit ratio drops after searcher pod restart (cold cache). Recovery takes minutes. Don't page on transient dips.

### Now what?
- Check which cache type (splitfooter, fastfields, shortlived) has the most misses
- Compare leaf splits/s with merge backlog (too many small splits = high fan-out)
- Check S3 GET rate (cache misses translate directly to S3 GETs)

---

### # Metastore - Is the metadata layer fast and reliable?

### So what?
**Healthy:** Request rate stable, p95 latency <100ms, zero errors.
**Concerning:** Latency spiking = PostgreSQL under pressure or network issues. Error rate rising = all downstream services affected (indexing, search, GC all depend on metastore).
**Gotcha:** Do not average p95 across instances. Metastore errors cascade system-wide because every operation needs metadata.

### Now what?
- Check which operations are slow (list_splits, publish_splits most common)
- Verify PostgreSQL health (connections, locks, disk)
- Check if error spike correlates with a deployment or config change

---

### # Memory & Resources - Is the cluster within safe resource bounds?

### So what?
**Healthy:** RSS well below k8s memory limit, allocated/RSS gap within 2-3x, in-flight data bounded.
**Concerning:** RSS approaching pod limit = OOMKill imminent. In-flight data growing = pipeline stall (data entering but not being processed).
**Gotcha:** RSS can be much higher than allocated due to memory-mapped files. A 2-3x gap is normal for searchers with large caches. Don't alarm on RSS alone without checking allocated.

### Now what?
- Identify hottest nodes by RSS
- Check which in-flight data component is largest (wal, indexer, rest_server)
- If searchers are memory-heavy, check cache size and consider reducing cache capacity

---

### # Storage & Object Store - Are S3 operations healthy and within limits?

### So what?
**Healthy:** GET/PUT rates stable, transfer rates proportional to indexing and search load.
**Concerning:** GET rate spiking without search traffic increase = cache regression. PUT rate spiking without indexing increase = excessive merge amplification.
**Gotcha:** S3 GETs include both search reads AND merge reads. High GET rate during merge cycles is normal. Check alongside cache hit ratio for diagnosis.

### Now what?
- Check which nodes are generating the most S3 GETs (top-list)
- Correlate GET spikes with cache miss spikes
- Monitor S3 costs (GETs and transfer are the primary cost drivers)

---

### # Garbage Collection - Is the janitor keeping storage clean?

### So what?
**Healthy:** GC runs executing on schedule (default: hourly), deleted splits/bytes reflect retention policy, GC duration reasonable.
**Concerning:** GC runs dropping to zero = janitor not running (silent failure, storage grows unbounded). GC deleting zero splits despite old data = retention misconfiguration.
**Gotcha:** If no node has the janitor role enabled, ALL janitor metrics are absent AND no GC happens. This is a silent storage leak.

### Now what?
- Verify janitor role is enabled on at least one node
- Check GC run outcome (success vs failure)
- Compare GC deleted bytes with storage upload bytes (should be proportional over time)

---

## Part 3: Cause-Effect Triage Chains (>= 20)

1. **If** Indexing Throughput (MB/s) drops > 50% **->** check Backpressure (us/s) **->** likely: indexer OOM, disk I/O bottleneck, merge backlog **->** check Memory RSS, Merge Backlog. (Mixed)
2. **If** Backpressure (us/s) rises from zero **->** check Pending Merges (count) **->** likely: merge workers CPU-starved, too many small splits **->** increase indexer CPU or adjust merge policy. (Inference)
3. **If** Merge Backlog (count) grows unbounded **->** check Indexing Throughput **->** likely: merge factor too low, commit_timeout too short creating many small splits **->** increase resources.heap_size or merge_factor. (Mixed)
4. **If** Ingest Request Rate drops to zero **->** check Ingest Error Rate, Metastore Request Rate **->** likely: upstream clients failing, metastore down, control plane unreachable **->** check client logs, metastore health. (Inference)
5. **If** Ingest Error Rate rises above 1% **->** check WAL Disk Usage, Metastore p95 Latency **->** likely: WAL full, metastore slow, schema validation failures **->** check WAL limits, PostgreSQL health. (Inference)
6. **If** Ingest p95 Latency spikes **->** check Ingest In-Flight count, Memory RSS **->** likely: backpressure from indexer, memory pressure, disk I/O on WAL **->** check indexer throughput, WAL disk. (Inference)
7. **If** WAL Disk Usage approaches limit **->** check Indexing Throughput, Shard State **->** likely: indexers not consuming shards fast enough **->** scale indexers or reduce ingest rate. (Inference)
8. **If** Cache Hit Ratio drops below 90% **->** check S3 GETs, Leaf Splits/s **->** likely: cache capacity too small, new query patterns, searcher restarts **->** increase cache capacity, check for cold cache. (Inference)
9. **If** Leaf Search Splits/s spikes **->** check Merge Backlog, Cache Hit Ratio **->** likely: too many small splits (merge backlog), new large index **->** wait for merge catchup or investigate index growth. (Mixed)
10. **If** S3 GET rate spikes **->** check Cache Hit Ratio, Leaf Splits/s **->** likely: cache misses, heavy query load, merge reads **->** check cache metrics, correlate with search traffic. (Inference)
11. **If** Metastore Request Rate drops to zero **->** check Metastore Error Rate, PostgreSQL connectivity **->** likely: PostgreSQL down, network partition **->** check PostgreSQL status, DNS resolution. (Confirmed)
12. **If** Metastore p95 Latency exceeds 500ms **->** check Metastore Request Rate, specific operations **->** likely: PostgreSQL slow queries, lock contention, connection pool exhaustion **->** check PostgreSQL metrics, reduce concurrent operations. (Inference)
13. **If** Metastore Error Rate spikes **->** check Indexing Throughput, Ingest Error Rate, GC Runs **->** likely: all operations cascade-fail when metastore is unhealthy **->** priority 1: restore metastore. (Confirmed)
14. **If** Memory RSS approaching pod limit **->** check Memory Allocated, In-Flight Data **->** likely: heap too small, cache too large, memory leak **->** increase pod memory limit or reduce heap/cache sizes. (Inference)
15. **If** In-Flight Data by Component shows WAL growing **->** check Indexing Throughput, Backpressure **->** likely: indexers not consuming data **->** check indexer health, scale indexers. (Inference)
16. **If** S3 PUT rate drops to zero **->** check Indexing Throughput, Merge Backlog **->** likely: no splits being created or merged **->** check indexer health, control plane scheduling. (Inference)
17. **If** GC Runs drops to zero **->** check that janitor role is enabled on at least one node **->** likely: janitor not scheduled, node crash **->** restart janitor node, check k8s pod status. (Inference)
18. **If** GC Deleted Bytes consistently zero despite old data **->** check retention policy configuration **->** likely: retention not configured, or period not yet elapsed **->** verify index retention settings. (Inference)
19. **If** Write Amplification Ratio exceeds 3x **->** check Merge Backlog, Indexing Throughput **->** likely: aggressive merge policy, many small splits being merged repeatedly **->** consider adjusting merge policy. (Inference)
20. **If** S3 GET/PUT Ratio drops below 1 **->** check Indexing Throughput, Merge Backlog **->** likely: heavy write phase (bulk ingest or merge storm) **->** normal during bulk operations, concerning if sustained during query-heavy periods. (Inference)
21. **If** Ingest Shards show all closed, none open **->** check Control Plane health, Metastore **->** likely: control plane cannot assign new shards **->** check control plane logs. (Inference)

---

## Part 4: Operational Playbooks (6-10)

### Playbook 1: Indexing Throughput Collapse
**Trigger:** Indexing Throughput (MB/s) drops >50% from baseline
**Decision rule:** If backpressure is rising AND throughput is falling, the pipeline is being throttled.
**Steps:**
1. Check **Indexing Throughput (MB/s)** to confirm the drop
2. Check **Backpressure (us/s)** — if rising, pipeline is throttled
3. Check **Merge Backlog (count)** — if growing, merges are consuming resources
4. Check **Memory RSS** on indexer pods — if near limit, OOM risk
5. Check **In-Flight Data by Component** — identify where data is accumulating
6. Check upstream source health (Kafka lag, ingest API client errors)
**Likely causes:** Indexer OOM, merge backlog consuming CPU, source failure, disk I/O saturation
**Next actions:** Scale indexer pods, increase heap size, adjust merge policy, check upstream sources
**Label:** Mixed

### Playbook 2: Ingest Pipeline Rejection
**Trigger:** Ingest Error Rate rises above 1%
**Decision rule:** If WAL is >80% full AND errors are rising, the ingest pipeline is saturated.
**Steps:**
1. Check **Ingest Error Rate (%)** for error magnitude
2. Check **WAL Disk & Memory Usage** against configured limits
3. Check **Ingest p95 Latency** for pipeline slowness
4. Check **Indexing Throughput** — if throughput is low, indexers aren't draining WAL
5. Check **Metastore p95 Latency** — metastore slowness cascades into ingest
**Likely causes:** WAL full, indexer overload, metastore unreachable, schema validation errors
**Next actions:** Scale indexers, increase WAL limits, fix metastore connectivity, check ingest payload format
**Label:** Inference

### Playbook 3: Search Latency Degradation
**Trigger:** Cache Hit Ratio drops below 90% AND Leaf Splits/s increases
**Decision rule:** If cache misses are rising AND S3 GETs are spiking, investigate cache health.
**Steps:**
1. Check **Cache Hit Ratio (%)** — which cache type is degrading?
2. Check **S3 GETs (req/s)** — are misses translating to storage reads?
3. Check **Leaf Splits/s** — are queries touching more splits than usual?
4. Check **Merge Backlog** — too many small splits increases search fan-out
5. Check **Cache Size (bytes)** — is cache near capacity?
6. Check if searcher pods recently restarted (cold cache)
**Likely causes:** Cache capacity exhausted, searcher restarts, merge backlog creating many small splits
**Next actions:** Increase cache capacity, wait for merge catchup, scale searchers
**Label:** Inference

### Playbook 4: Metastore Cascade Failure
**Trigger:** Metastore Error Rate spikes above 0%
**Decision rule:** Any sustained metastore errors are critical because all services depend on it.
**Steps:**
1. Check **Metastore Error Rate** and **Metastore Request Rate** for scope
2. Check **Metastore p95 Latency** — is it slow or completely failing?
3. Check **Top Metastore Operations** — which operations are failing?
4. Check **Indexing Throughput** — should drop if metastore is down
5. Check **Ingest Error Rate** — should rise if metastore is down
6. Check **GC Runs** — should stop if metastore is down
**Likely causes:** PostgreSQL failure, network partition, connection pool exhaustion, disk full on PG
**Next actions:** Restore PostgreSQL immediately, check PG connections/locks, verify DNS/network
**Label:** Confirmed

### Playbook 5: Storage Cost Spike
**Trigger:** S3 request rate or transfer bytes significantly above baseline
**Decision rule:** If S3 costs are rising, identify whether it's read-heavy (search/cache misses) or write-heavy (indexing/merge).
**Steps:**
1. Check **S3 GETs vs PUTs** — read-heavy or write-heavy?
2. Check **S3 Transfer Rate** — downloads vs uploads?
3. Check **Cache Hit Ratio** — cache misses drive GETs
4. Check **Write Amplification Ratio** — high ratio = expensive merges
5. Check **Top Nodes by S3 GETs** — identify hotspots
**Likely causes:** Cache regression, merge storms, heavy query workload, index growth
**Next actions:** Increase cache capacity, adjust merge policy, review query patterns
**Label:** Inference

### Playbook 6: Silent Janitor Failure
**Trigger:** GC Runs drops to zero for >2 hours
**Decision rule:** If janitor metrics disappear, no GC is happening and storage will grow unbounded.
**Steps:**
1. Check **GC Runs (runs/min)** — confirm zero
2. Check k8s pod status for janitor role
3. Check **Metastore p95 Latency** — janitor needs metastore to find deletable splits
4. Check S3 storage costs over past 7 days — are they growing?
5. Check if janitor role is configured on at least one node
**Likely causes:** Janitor pod crashed, janitor role disabled, metastore unreachable
**Next actions:** Restart janitor pod, enable janitor role, fix metastore connectivity
**Label:** Inference

### Playbook 7: Memory Pressure / OOM Risk
**Trigger:** Memory RSS on any node approaches k8s memory limit
**Decision rule:** If RSS > 85% of pod memory limit, OOM kill is imminent.
**Steps:**
1. Check **Memory RSS** and **Memory Allocated** — what's the gap?
2. Check **In-Flight Data by Component** — is data accumulating in pipeline?
3. Identify node role (indexer vs searcher) — different remediation paths
4. For indexers: check heap size, number of concurrent pipelines
5. For searchers: check cache capacity, concurrent query count
6. Check if recent deployment changed memory limits or configuration
**Likely causes:** Heap too small, cache too large, too many concurrent operations, memory leak
**Next actions:** Increase pod memory limit, reduce heap/cache, scale horizontally, check for leaks
**Label:** Inference


---

# Quickwit Caveats & Footguns

## High-cardinality dimensions to avoid

- **[indexing-throughput, ingest-health]** The `index` label on metrics can have unbounded cardinality if users create many indexes dynamically. Use `context.index` group-by with a conservative top-N (10). Quickwit supports disabling per-index metrics to reduce cardinality. (Inference based on source code)
- **[memory-resources]** The `component` label on `quickwit_memory_in_flight_data_bytes` has ~15 values. Safe for group-by, but adding a second group-by level (e.g., by instance) can produce 150+ series. Keep to one group-by level in timeseries. (Inference)
- **[search-performance]** Avoid grouping cache metrics by both `cache` and `scope.name` simultaneously on timeseries. 3 caches x 50 searchers = 150 lines. Use top-list instead. (Inference)

## Misleading metrics and wrong aggregations

- **[indexing-throughput]** `quickwit_indexing_processed_bytes` measures bytes entering the pipeline, not bytes written to S3. Actual S3 upload volume is `quickwit_storage_object_storage_upload_num_bytes`. Confusing the two gives a misleading view of storage costs. ([Grafana Dashboard](https://github.com/quickwit-oss/quickwit/tree/main/monitoring/grafana/dashboards))
- **[memory-resources]** `quickwit_memory_allocated_bytes` (jemalloc allocated) is NOT the same as RSS. RSS (`quickwit_memory_resident_bytes`) includes memory-mapped files and is what the OOM killer uses. Always compare both. ([Source code](https://github.com/quickwit-oss/quickwit/blob/main/quickwit/quickwit-common/src/metrics.rs))
- **[metastore-performance]** Do NOT average histogram percentiles across instances. p95 of instance A + p95 of instance B / 2 is NOT the fleet p95. Use the histogram aggregation natively. (Inference)
- **[storage-object-store]** `quickwit_storage_object_storage_gets_total` includes both search reads AND merge reads. High GET rate during merge cycles is normal and does not indicate search load increase. (Inference)

## Unit pitfalls

- **[indexing-throughput]** `quickwit_indexing_backpressure_micros` is in microseconds, not milliseconds or seconds. Display as us/s when using per-second normalization. Mislabeling as ms makes backpressure look 1000x less severe. ([Grafana Dashboard](https://github.com/quickwit-oss/quickwit/tree/main/monitoring/grafana/dashboards))
- **[ingest-health]** `quickwit_ingest_grpc_request_duration_seconds` is in seconds, matching Prometheus histogram convention. The `_bucket` suffix is just the Prometheus exposition format — the metric value is already in seconds. (Inference)
- **[memory-resources]** All memory metrics are in raw bytes. The normalizer should use `data` type with unit `B` to get automatic KiB/MiB/GiB scaling. Using `custom` with "bytes" label prevents auto-scaling. (Inference)

## Sampling/temporality pitfalls

- **[indexing-throughput, storage-object-store, ingest-health, search-performance]** Counter temporality (delta vs cumulative) depends on the collection pipeline. Prometheus native scrape produces cumulative counters (use `rate`). OTel Collector with Prometheus receiver may produce delta counters (use `per-second`). Stage 2 discovery will confirm the correct post-function. (Inference)
- **[indexing-throughput]** `quickwit_indexing_processed_docs_total` can have step-function behavior: counts increment in bursts when splits are committed (every `commit_timeout_secs`, default 60s). Short scrape intervals show flat lines interrupted by jumps. This is normal, not a pipeline stall. ([Index Configuration](https://quickwit.io/docs/configuration/index-config))
- **[storage-gc]** `quickwit_janitor_gc_runs` increments in batches during scheduled retention evaluation. Flat periods between evaluations are normal (default: hourly). (Inference)

## "This looks bad but isn't"

- **[indexing-throughput]** Pending merge operations temporarily spiking after a bulk ingest is normal. The merge policy allows up to `max_merge_factor` (default 12) operations before backpressure kicks in. Only sustained growth is concerning. ([Index Configuration](https://quickwit.io/docs/configuration/index-config))
- **[search-performance]** Cache hit ratio dropping temporarily after a searcher pod restart is expected — the cache is in-memory and needs to warm up. Recovery should take minutes, not hours. (Inference)
- **[ingest-health]** `quickwit_ingest_grpc_requests_in_flight` spiking during a batch ingest operation is normal. Concern only if it stays elevated AND latency increases. (Inference)
- **[memory-resources]** `quickwit_memory_resident_bytes` can be significantly higher than `quickwit_memory_allocated_bytes` due to memory-mapped files. A 2-3x gap is normal for searchers with large split footer caches. (Inference based on jemalloc behavior)

## Optional-feature traps (metrics absent unless X enabled)

- **[ingest-health]** WAL metrics (`quickwit_ingest_wal_disk_used_bytes`, `quickwit_ingest_wal_memory_used_bytes`) are ONLY populated with ingest v2 (shard-based ingestion). Using ingest v1? These metrics will report 0 or a constant value. Do not alert on them. ([GitHub Issue #5547](https://github.com/quickwit-oss/quickwit/issues/5547))
- **[ingest-health]** `quickwit_ingest_shards` requires ingest v2. With ingest v1, this metric has no data. (Inference from source code)
- **[search-performance]** Cache metrics require the searcher role to be running. Indexer-only nodes will not produce `quickwit_cache_*` metrics. (Inference)
- **[storage-gc]** Janitor metrics require the janitor role to be running. If no node has the janitor role enabled, all `quickwit_janitor_*` metrics will be absent — AND no GC is happening, so storage grows unbounded. This is a silent failure mode. (Inference)
- **[metastore-performance]** If using file-based metastore instead of PostgreSQL, metastore gRPC metrics may behave differently (single-node only, no concurrent access). The dashboard assumes PostgreSQL-backed metastore. ([Deployment Modes](https://quickwit.io/docs/deployment/deployment-modes))


---

