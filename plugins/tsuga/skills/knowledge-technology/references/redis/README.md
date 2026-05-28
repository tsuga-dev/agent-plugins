# Redis Integration Context Bundle

## Metadata
**Technology:** Redis  
**Deployment:** self-hosted  
**Environment:** prod  
**Persona:** SRE  
**Telemetry preference:** mixed  
**Integration scope:** core service only  
**Primary use-case:** reliability and performance

## How to use this bundle
- Use `01_redis_metrics.csv` as the curated source of truth for metric semantics, units, and safe query math.
- Use `02_redis_dashboard_plan.yaml` as the dashboard blueprint (sections, widgets, derived signals, triage chains, playbooks).
- Use `03_redis_state.yaml` for machine-readable stage state, reconciliation outcomes, and unknowns.
- Use `04_redis_memory.md` for human-readable migration/discovery history and rationale.
- Stage 2 creates/refreshes `05_redis_metric_catalog.csv` as the discovered inventory and context-key curation layer.

## What it is and what "good" looks like

### Confirmed by sources
- Redis is an in-memory data structure server used for cache/session/queue-like workloads.
- Command execution is effectively single-threaded; one expensive command can block the event loop.
- Healthy posture means stable command throughput, low rejected connections, controlled memory pressure, and bounded latency.
- Fork-related persistence operations (BGSAVE/BGREWRITEAOF) can create transient latency spikes.

### Best-practice inference
- Incident shape 1: memory pressure or eviction storm. Start with `memory-capacity`.
- Incident shape 2: latency regression from command mix or fork behavior. Start with `performance-latency`.
- Incident shape 3: admission failures from connection exhaustion. Start with `connections-clients`.

## Key concepts

### Glossary

| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| maxmemory | Configured memory ceiling | Denominator for memory utilization and eviction pressure | memory-capacity |
| maxmemory-policy | Eviction policy when maxmemory is reached | Determines eviction vs OOM write failures | memory-capacity |
| used_memory | Allocator-tracked Redis memory | Main memory pressure numerator | memory-capacity |
| used_memory_rss | OS-visible resident memory | Captures fragmentation/COW overhead | memory-capacity |
| fragmentation ratio | `rss / used` ratio | <1 can indicate swap risk, >1.5 sustained suggests waste | memory-capacity |
| eviction | Key removal due to memory pressure | Expected for some cache policies, harmful for data-store patterns | memory-capacity |
| expiration | TTL-driven key deletion | Bursty expiration can impact latency | throughput-performance |
| commands.processed | Monotonic command counter | Primary throughput signal via per-second math | throughput-performance |
| commands (instantaneous) | Snapshot ops/s gauge | Noisy sampled gauge; secondary only | throughput-performance |
| keyspace hits/misses | Lookup outcomes | Input to cache-hit ratio | throughput-performance |
| blocked clients | Clients waiting on blocking ops | Consumer bottleneck indicator | connections-clients |
| rejected connections | New connections refused | Immediate admission failure signal | availability-health |
| slowlog | Slow command execution samples | Helps identify blocking command patterns | performance-latency |
| latest_fork | Duration of last fork operation | Persistence overhead proxy | performance-latency/persistence |
| RDB snapshot | Point-in-time persistence file | Save health affects recovery/data safety posture | persistence |
| AOF | Append-only persistence log | Fsync/rewrites can affect latency | persistence |
| replication offset | Master/replica progress position | Basis for lag interpretation | replication |
| replication backlog | Buffer for partial resync | Too small backlog can force full resyncs | replication |
| role | Primary vs replica identity | Topology-aware interpretation | replication |
| state (CPU) | CPU state dimension | Main-thread utilization diagnosis | resource-utilization |

### Concept Map

```text
Client request -> enters -> Redis event loop (why: single-threaded command execution path)
Event loop -> executes -> command workload (why: throughput and latency are command-shape driven)
Expensive/O(N) commands -> block -> subsequent commands (why: tail latency and queueing spikes)
commands.processed -> drives -> throughput baseline (why: primary load trend signal)
keyspace hits/misses -> derive -> cache-hit ratio (why: cache effectiveness)
maxmemory -> constrains -> used memory (why: memory saturation boundary)
maxmemory-policy -> decides -> eviction vs OOM behavior (why: failure mode under pressure)
used_memory + rss -> derive -> fragmentation posture (why: allocator/OS overhead visibility)
evictions/expirations -> affect -> latency and hit ratio (why: churn and active expiry pressure)
BGSAVE/BGREWRITEAOF -> trigger -> fork overhead (why: persistence-induced latency spikes)
fork overhead -> increases -> request latency risk (why: copy-on-write and memory pressure)
connected clients -> bounded by -> maxclients (why: admission headroom)
rejected connections -> indicate -> capacity breach (why: immediate client impact)
replication offsets -> reveal -> lag between primary and replicas (why: read staleness/failover risk)
replication backlog -> enables -> partial resync (why: avoids expensive full sync)
service/env/cluster/scope dimensions -> enable -> ownership and blast-radius isolation (why: faster triage)
```

### Entities and dimensions

| Entity/Dimension | Why useful | Cardinality risk | Safe top-N | Do NOT group-by guidance |
|---|---|---|---|---|
| `context.scope` | Instance identity for Redis node/pod | Medium | 20 | Avoid pairing with high-card command dimensions by default |
| `context.env` | Environment filter | Low | 5 | Keep as global filter |
| `context.team` | Ownership filter | Low | 10 | Keep as global filter |
| `context.k8s.cluster.name` | Multi-cluster blast radius | Low-Med | 10 | Avoid deep split unless needed |
| `context.k8s.namespace.name` | Tenant/workload split | Medium | 20 | Avoid on top-line KPIs |
| `context.service.name` | Service-level correlation | Medium | 20 | Use for scoped investigations |
| `context.db` | Redis logical DB split | Low | 16 | Most cluster-mode installs effectively use db0 |
| `context.state` | CPU state split | Low | 6 | Use only on CPU metrics |
| `context.cmd` | Per-command diagnostics | High | 10 | Never unbounded in overview |
| `context.redis.version` | Version drift/debug | Low | 5 | Not a primary KPI dimension |

### Tsuga field mapping

| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| Redis instance host/pod scope | `context.scope` | Must-exist |
| Environment | `context.env` | Must-exist |
| Team | `context.team` | Must-exist |
| Kubernetes cluster | `context.k8s.cluster.name` | Optional |
| Kubernetes namespace | `context.k8s.namespace.name` | Optional |
| Service | `context.service.name` | Optional |
| Redis database number | `context.db` | Optional (metric-specific) |
| CPU state | `context.state` | Optional (metric-specific) |
| Command name | `context.cmd` | Optional (metric-specific, high-cardinality) |
| Redis version | `context.redis.version` | Optional |

## Golden signals

### Confirmed by sources
| Signal | Meaning for Redis | Typical degradations | Best telemetry | Section question |
|---|---|---|---|---|
| Traffic | Command and network workload | Traffic surge, hot keys, client churn | `redis.commands.processed`, `redis.net.input/output` | Is Redis handling expected throughput? |
| Errors | Admission or write-failure outcomes | maxclients exhaustion, OOM/noeviction, persistence failure | `redis.connections.rejected`, persistence proxies | Are instances reachable and error-free? |
| Latency | Command execution responsiveness | O(N) commands, fork overhead, swap/THP issues | `redis.latest_fork`, optional `redis.cmd.*` | Is latency within acceptable bounds? |
| Saturation | Proximity to memory/CPU/connection limits | memory ceiling, single-thread CPU saturation, blocked consumers | `redis.memory.*`, `redis.cpu.time`, clients metrics | Are we nearing hard limits? |

### Best-practice inference
- Cache hit ratio is the fastest signal for cache-efficiency regressions when workload is primarily cache-oriented.
- Fork duration trend is a practical early warning for persistence-related latency risk.

## Telemetry sources

### Confirmed by sources
| Source type | How collected | What it provides | Pros/cons | Common pitfalls |
|---|---|---|---|---|
| Redis INFO | Direct server introspection | Core server/clients/memory/persistence/replication stats | Canonical but raw/unstructured | Feature-dependent sections can appear absent by design |
| OTel Redis receiver | Collector polling INFO | Normalized `redis.*` metric families | Good default integration surface | Optional families disabled by default |
| Prometheus redis_exporter | Exporter scrape bridge | Wider metric surface including slowlog-related counters | Broad and mature | Cardinality risks with optional exporter flags |
| Slowlog/Latency commands | Redis command diagnostics | Slow command and latency-event evidence | High triage value | Not always ingested as metrics by default |

### Best-practice inference
- "No data" on optional per-command/per-latency families often means feature disabled, not healthy zero.
- Prefer counter-derived rates over instantaneous sampled gauges for decision-grade throughput trends.

## Caveats and footguns
- **[throughput-performance]** `redis.commands` is a sampled gauge, not a monotonic counter; use `redis.commands.processed` with per-second math.
- **[performance-latency]** slowlog excludes queueing and network time; client-observed latency can be much worse.
- **[memory-capacity]** fragmentation ratio can be misleading at low memory usage and during transient allocator behavior.
- **[memory-capacity]** `maxmemory=0` makes utilization percentage invalid.
- **[performance-latency, persistence]** fork-aligned latency spikes are expected during persistence operations; correlate before paging.
- **[connections-clients]** high client count alone is not a leak signal; ratio to maxclients matters more.
- **[performance-latency, throughput-performance]** `context.cmd` is high cardinality; always bound with Top-N.
- **[replication]** replication metrics absent in standalone mode are expected, not necessarily telemetry failure.

## Confirmed Tsuga prefixes
- `redis.*` — **CONFIRMED** (29 metrics discovered in Tsuga during Stage 2 reconciliation)

## Discovery status
Discovery: completed in current Stage 2 pass.
- Metrics found: 29 (`redis.*`)
- Curated metrics in 01: 38
- Confirmed in Tsuga: 29
- Missing from Tsuga (mostly optional/disabled families): 9

## Top sources
1. https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/redisreceiver/documentation.md  
   Why: canonical OTel Redis metric names/types/units.
2. https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/redisreceiver/metadata.yaml  
   Why: source-level metric metadata and attributes.
3. https://redis.io/docs/latest/commands/info/  
   Why: authoritative semantics for INFO-backed fields.
4. https://redis.io/docs/latest/develop/reference/eviction/  
   Why: eviction/maxmemory behavior and failure modes.
5. https://redis.io/docs/latest/operate/oss_and_stack/management/optimization/latency/  
   Why: latency diagnosis and fork/THP caveats.
6. https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/  
   Why: RDB/AOF behavior and persistence tradeoffs.
7. https://redis.io/docs/latest/operate/oss_and_stack/management/replication/  
   Why: replication/backlog/full-sync semantics.
8. https://redis.io/tutorials/operate/redis-at-scale/observability/  
   Why: Redis operational observability guidance.
9. https://github.com/oliver006/redis_exporter  
   Why: exporter-side optional metric and cardinality caveats.
10. https://redis.io/docs/latest/operate/oss_and_stack/management/optimization/memory-optimization/  
    Why: fragmentation and memory behavior interpretation.
