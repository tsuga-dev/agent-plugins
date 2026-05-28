# PostgreSQL Integration Context Bundle

## Metadata
**Technology:** PostgreSQL  
**Deployment:** self-hosted  
**Environment:** prod  
**Persona:** SRE  
**Telemetry preference:** mixed  
**Integration scope:** core service only  
**Primary use-case:** reliability and performance

## How to use this bundle
- Use `01_postgresql_metrics.csv` as the curated source of truth for metric semantics, units, and safe query math.
- Use `02_postgresql_dashboard_plan.yaml` as the dashboard blueprint (sections, widgets, derived signals, triage chains, playbooks).
- Use `03_postgresql_state.yaml` for machine-readable pipeline state, reconciliation outcomes, and unresolved unknowns.
- Use `04_postgresql_memory.md` for human-readable migration and reconciliation memory.
- Stage 2 creates/refreshes `05_postgresql_metric_catalog.csv` as the discovered inventory and context-key curation layer.

## What it is and what "good" looks like

### Confirmed by sources
- PostgreSQL is a Tier-0 relational datastore; most application paths depend on it for correctness and availability.
- OTel PostgreSQL receiver default metrics cover connections, transactions, cache behavior, table/index stats, bgwriter/checkpoints, and size growth.
- Healthy posture means stable commit throughput, low rollback/deadlock pressure, high cache-hit ratio, and controlled checkpoint/bgwriter pressure.
- Table maintenance posture matters: dead tuples must stay bounded, and vacuum activity must keep up.

### Best-practice inference
- Incident shape 1: connection exhaustion. Start with `availability-connections`.
- Incident shape 2: cache miss storm / storage I/O pressure. Start with `cache-performance` then `bgwriter-checkpoints`.
- Incident shape 3: vacuum starvation and table bloat. Start with `table-health`, then `storage-growth`.

## Key concepts

### Glossary

| Term | Definition | Operational meaning | Dashboard section |
|---|---|---|---|
| Backend | Active PostgreSQL server process handling a client session | Primary connection-capacity signal | availability-connections |
| `max_connections` | Hard cap on concurrent backend connections | Capacity ceiling for admission | availability-connections |
| Commit | Successful transaction end | Core successful write activity | throughput |
| Rollback | Aborted transaction end | Error/conflict symptom | errors-conflicts |
| Deadlock | Circular lock wait between transactions | Immediate correctness/latency risk | errors-conflicts |
| Cache hit | Read served from shared buffers | Good memory efficiency | cache-performance |
| Cache miss | Read requiring disk access | Potential latency/I/O pressure | cache-performance |
| Shared buffers | PostgreSQL in-memory page cache | Main cache efficiency control | cache-performance |
| Vacuum | Background cleanup of dead tuples | Prevents bloat and planner drift | table-health |
| Dead tuple | Row version not visible to active transactions | Bloat precursor | table-health |
| Live tuple | Currently visible row version | Baseline denominator for dead/live ratio | table-health |
| Checkpoint | Durability flush boundary | Write-pressure and recovery behavior | bgwriter-checkpoints |
| Bgwriter | Background process flushing dirty buffers | Reduces write spikes on backends | bgwriter-checkpoints |
| Table size | Current storage footprint of a table | Growth/bloat attribution | storage-growth |
| Index size | Current storage footprint of an index | Storage and maintenance overhead | storage-growth |
| DB size | Total database footprint | Capacity planning signal | storage-growth |
| Tuple fetched | Rows fetched by query execution paths | Read-path load proxy | tuple-io |
| Tuple returned | Rows returned from scans | Read amplification context | tuple-io |
| Tuple inserted/updated/deleted | DML write activity by row action | Workload-shape signal | tuple-io |
| `context.postgresql.database.name` | Database dimension | Main safe attribution key | all |
| `context.postgresql.table.name` | Table dimension | High-cardinality attribution key | table-health / storage-growth |
| `context.operation` | Operation type (insert/update/delete/hot_update) | Write pattern split | tuple-io |

### Concept Map

```text
Client application -> sends -> SQL request (why: request source and load driver)
SQL request -> consumes -> backend connection slot (why: bounded by max_connections)
Backend connection slot -> contributes to -> connection utilization (why: admission headroom KPI)
Connection utilization -> constrained by -> max_connections (why: hard refusal threshold)
Transaction -> ends as -> commit or rollback (why: throughput vs failure split)
Rollback growth -> indicates -> conflict or app failure pressure (why: early reliability degradation)
Concurrent transactions -> contend on -> locks (why: deadlock and latency amplification)
Lock contention -> increases -> deadlocks/rollbacks (why: user-visible errors and retries)
Read query -> served by -> shared buffers or disk (why: cache efficiency determines latency)
Cache hit ratio -> derived from -> blks_hit vs blks_read (why: fast latency proxy)
Cache miss growth -> increases -> storage I/O pressure (why: rising query latency risk)
Write workload -> produces -> dirty buffers and WAL activity (why: checkpoint/bgwriter pressure)
Bgwriter/checkpoint activity -> controls -> flush cadence (why: write-stall risk when unstable)
UPDATE/DELETE -> creates -> dead tuples (why: maintenance debt accumulation)
Autovacuum/VACUUM -> removes -> dead tuples (why: bloat and planner health control)
Dead tuple backlog -> inflates -> table and index size (why: storage growth and slower scans)
Database/table/index size -> drives -> capacity planning posture (why: growth and bloat tracking)
Service/team/env/cluster context -> maps to -> triage ownership filters (why: faster blast-radius isolation)
```

### Entities and dimensions

| Entity/Dimension | Why useful | Cardinality risk | Safe top-N | Do NOT group-by guidance |
|---|---|---|---|---|
| `context.env` | Environment routing | Low | 5 | Keep as global filter, not deep split |
| `context.team` | Ownership routing | Low | 10 | Avoid as primary technical root-cause split |
| `context.scope.name` | Instance identity | Low-Med | 20 | Avoid pairing with high-card table/index by default |
| `context.service.instance.id` | Alternative instance identity | Medium | 20 | Prefer one instance dimension, not both |
| `context.postgresql.database.name` | Database-level blast radius | Medium | 20 | Keep bounded |
| `context.postgresql.table.name` | Table hotspot detection | High | 20 | Never unbounded |
| `context.postgresql.index.name` | Index hotspot detection | Very high | 10 | Never in overview widgets |
| `context.operation` | DML split | Low | 5 | Use only where metric supports it |
| `context.state` | dead/live split on tuple metrics | Low | 2 | Use only on `postgresql.rows` |
| `context.source` | backend/bgwriter/checkpoint source split | Low | 5 | Use only on bgwriter write metrics |
| `context.k8s.cluster.name` | Multi-cluster scope | Low-Med | 10 | Optional only if k8s-enriched |

### Tsuga field mapping

| Vendor/exporter dimension | Recommended context.* key | Must-exist vs optional |
|---|---|---|
| PostgreSQL instance | `context.scope.name` | Optional (recommended) |
| Instance ID | `context.service.instance.id` | Optional |
| Database | `context.postgresql.database.name` | Optional (highly useful) |
| Table | `context.postgresql.table.name` | Optional |
| Index | `context.postgresql.index.name` | Optional |
| Operation type | `context.operation` | Optional (metric-specific) |
| Bgwriter source | `context.source` | Optional (metric-specific) |
| Row state | `context.state` | Optional (metric-specific) |
| Environment | `context.env` | Must-exist |
| Team | `context.team` | Must-exist |
| K8s cluster | `context.k8s.cluster.name` | Optional |

## Golden signals

### Confirmed by sources
| Signal | What it means for PostgreSQL | Typical degradation causes | Best telemetry sources | What people page on | Section questions |
|---|---|---|---|---|---|
| Traffic | DB transactional and tuple workload | App surge, batch jobs, lock stalls | commits, rollbacks, operations, tup_* | Sudden rate collapse or abnormal surge | Is DB handling expected workload? |
| Errors | Transaction failures and lock conflict | App logic faults, lock ordering, contention | rollbacks, deadlocks | Sustained rollback/deadlock growth | Are failures conflict-driven or app-driven? |
| Latency proxy | Cache misses and write-path pressure | Undersized cache, slow storage, checkpoint storms | blks_hit/blks_read, bgwriter metrics | Cache-hit drop + read spike + checkpoint stress | Is slowness from cache miss or checkpoint pressure? |
| Saturation | Connection and maintenance headroom | Connection leaks, vacuum lag, bloat | backends vs connection.max, rows(state=dead), table.vacuum.count | Connection util >80% or dead tuple growth | Are we near hard caps or cleanup lag? |

### Best-practice inference
- Cache hit ratio and connection utilization are first-glance KPI candidates.
- Dead tuple ratio plus vacuum rate is the fastest maintenance debt indicator.

## Telemetry sources

### Confirmed by sources
| Source type | How collected | What it provides | Pros/cons | Common pitfalls |
|---|---|---|---|---|
| OTel `postgresqlreceiver` | SQL polling over pg_stat* views | 27 default metrics across core DB health domains | Simple standard pipeline; broad baseline visibility | Missing per-query (`pg_stat_statements`) and deep lock-wait detail by default |
| PostgreSQL native views | Direct SQL in psql/admin tooling | Ground truth for lock details, replication, query-level diagnostics | Most detailed | Not normalized; not dashboard-ready without modeling |
| PostgreSQL docs | Official metric/behavior semantics | Authoritative interpretation | Reliable reference | Requires mapping to Tsuga context keys |

### Best-practice inference
- "No data" is usually receiver permission/config/scope drift, not necessarily healthy zero.
- Some dimensions (table/index) are intentionally high-card and must always be bounded.

## Caveats and footguns
- **[availability-connections]** `postgresql.backends` is a current-value signal; do not use per-second math.
- **[availability-connections]** `postgresql.connection.max` is config-state and usually static.
- **[cache-performance]** Cache-hit ratio is noisy after restart or `pg_stat_reset`.
- **[cache-performance]** Ratio math can divide by zero when there is no read activity.
- **[table-health]** `context.postgresql.table.name` is high cardinality; keep tight top-N.
- **[table-health]** Dead tuples can accumulate if long-running transactions block cleanup.
- **[bgwriter-checkpoints]** Frequent checkpoints plus long duration usually implies I/O pressure.
- **[bgwriter-checkpoints]** `context.source` split is mandatory for backend-vs-bgwriter write diagnosis.
- **[errors-conflicts]** Deadlocks are low-volume but high-severity.
- **[storage-growth]** Table/index growth can reflect bloat, not just legitimate data growth.
- **[tuple-io]** Large fetched-vs-returned gaps can indicate scan inefficiency.

## Confirmed Tsuga prefixes
- `postgresql.*` — **CONFIRMED** (27 metrics discovered in prior Stage 2 run)

## Discovery status
Discovery: completed in prior Stage 2 run.
- Metrics found: 27
- Metrics confirmed in curated inventory: 27
- Missing curated metrics: 0
- Known gaps: replication lag and lock-detail metrics are not covered by default OTel receiver output

## Top sources
1. https://www.postgresql.org/docs/current/  
   Why: Canonical PostgreSQL behavior and operational semantics.
2. https://www.postgresql.org/docs/current/monitoring-stats.html  
   Why: Authoritative definitions for pg_stat metrics and interpretation.
3. https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/postgresqlreceiver/README.md  
   Why: OTel receiver metric names, units, and collection behavior.
4. https://www.postgresql.org/docs/current/runtime-config-resource.html  
   Why: Connection and memory configuration constraints (`max_connections`, shared buffers).
5. https://www.postgresql.org/docs/current/runtime-config-autovacuum.html  
   Why: Autovacuum control surface for dead tuple and bloat mitigation.
6. https://www.postgresql.org/docs/current/routine-vacuuming.html  
   Why: Vacuum strategy and maintenance caveats.
7. https://www.postgresql.org/docs/current/wal-configuration.html  
   Why: Checkpoint/WAL pressure behavior and tuning.
8. https://www.postgresql.org/docs/current/monitoring-locks.html  
   Why: Lock/deadlock diagnostics for conflict triage.
9. https://www.postgresql.org/docs/current/pgstatstatements.html  
   Why: Coverage gap reference for query-level observability.
10. https://www.postgresql.org/docs/current/sql-vacuum.html  
    Why: Operational vacuum command behavior and constraints.
