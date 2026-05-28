# Cassandra

Wide-column distributed NoSQL. Healthy: low error rate, bounded p99, compaction keeping up, low hints, low tombstone scans.

## Incident shapes

- **Read latency regression** — read p99 spikes → check cache, compaction, tombstones
- **Compaction backlog** — pending compactions climb → writes outpacing compaction
- **Tombstone storm** — scanned tombstones dominate live rows → queue-like table or TTL issue
- **Hint accumulation** — `total_hints.in_progress` rises → replicas unreachable
- **Hot coordinator** — `coordinator.read` / `scan` skewed on one node → hot partition or token imbalance

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `cassandra.client.request.count` | req/s | Throughput baseline |
| `cassandra.client.request.error.count` | err/s | Replica unavailability / client issue |
| `cassandra.client.request.read.latency.99p` | ms | Read p99 |
| `cassandra.client.request.write.latency.99p` | ms | Write p99 |
| `cassandra.client.request.range_slice.latency.99p` | ms | Range-scan p99 (expensive) |
| `cassandra.compaction.tasks.pending` | count | > 100 sustained = falling behind |
| `cassandra.compaction.tasks.completed` | count | Compaction throughput |
| `cassandra.storage.load.count` | bytes | Per-node data load |
| `cassandra.storage.total_hints.count` | count | Stored hints (offline replicas) |
| `cassandra.storage.total_hints.in_progress.count` | count | Active hint handoff |
| `cassandra.table.bloom_filter.false_ratio` | ratio | > 0.01 = bloom ineffective |
| `cassandra.table.tombstone_scanned` | count | Tombstones examined per read |
| `cassandra.table.disk.used` | bytes | Per-table footprint |
| `cassandra.table.operation.count` / `latency` | — | Per-table stats |

## Derived signals

- `request.error.count / request.count` — error rate. Baseline ≈ 0.
- `compaction.tasks.pending` — backlog. > 100 after flush = behind.
- `table.tombstone_scanned / table.operation.count` — tombstone pressure. Rising on time-series or queue-like tables = TTL review needed.

## Log patterns

- `TombstoneOverwhelmingException` — single query exceeded tombstone scan limit
- `Compacting large partition` — hot-partition warning
- `Read 1000 live rows and N tombstone cells` — N ≫ 1000 = tombstone storm
- `Hinted handoff started for` / `completed for` — replay activity
- `Flushing largest memtable` — writes outpacing flush
- `GC Young / Old generation pause` — pauses > 200ms correlate with client timeouts
- `Timed out waiting for N responses` — coordinator couldn't reach replicas
- `Not enough live nodes` — quorum lost

## Gotchas

- Latency percentiles are per-node; a hot node hides in cluster averages.
- Tombstone scans rise with `IN` clauses over many TTL'd keys — often a modeling issue (Cassandra used as a queue).
- GC pauses look like latency incidents; pair with JVM metrics (`jvm.md`) before blaming Cassandra.
- `nodetool repair` is heavy and looks like an incident; check for scheduled repair activity first.
- Token imbalance creates hot-node hotspots that aggregate metrics hide. Compare disk.used per node.
