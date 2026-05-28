# PostgreSQL

Tier-0 relational datastore. Healthy: stable commits, cache-hit > 0.99, no connection pressure, vacuum keeping up with dead tuples.

## Incident shapes

- **Connection exhaustion** — backends near `connection.max` → check connection utilization
- **Cache miss storm** — `blks_read` up, hit ratio drops → check bgwriter + block IO
- **Vacuum starvation** — dead tuples grow faster than vacuum catches up → check table-health
- **Replica lag** — primary WAL exceeds replica replay → check replication
- **Checkpoint pressure** — frequent checkpoints + high WriteIOPS → check bgwriter

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `postgresql.backends` | connections | Active count; use `max` aggregation |
| `postgresql.connection.max` | connections | Denominator for utilization |
| `postgresql.commits` | txns/s | Write-activity baseline |
| `postgresql.rollbacks` | txns/s | Conflict / error rate |
| `postgresql.deadlocks` | count | Any nonzero rate = red flag |
| `postgresql.blks_hit` | blocks/s | Cache-hit numerator |
| `postgresql.blks_read` | blocks/s | Disk reads; rise = cache pressure |
| `postgresql.bgwriter.checkpoint.count` | 1/s | Frequent checkpoints = write pressure |
| `postgresql.bgwriter.duration` | ms | Long checkpoints correlate with write-latency spikes |
| `postgresql.rows` (state=dead) | rows | Bloat numerator |
| `postgresql.table.vacuum.count` | 1/s | 0 while dead rows grow = vacuum starvation |
| `postgresql.db_size` | bytes | Sudden jumps = bulk insert or missing vacuum |
| `postgresql.operations` (context.operation) | ops/s | Insert / update / delete / hot_update mix |

RDS additions: `FreeStorageSpace`, `ReplicaLag`, `WriteIOPS`, `ReadIOPS`, `WriteLatency`, `ReadLatency`, `BurstBalance`, `DBLoad`. See `aws-rds.md`.

## Derived signals

- `backends / connection.max` — connection utilization. Alert > 0.85.
- `blks_hit / (blks_hit + blks_read)` — cache hit ratio. OLTP healthy > 0.99; < 0.95 sustained = cache pressure.
- `rollbacks / (commits + rollbacks)` — rollback ratio. Baseline < 0.01.
- `rows{state=dead} / rows{state=live}` — dead-tuple ratio. > 0.2 on hot tables = bloat risk.

## Log patterns

- `FATAL: remaining connection slots are reserved` / `too many clients already` — connection exhaustion
- `ERROR: deadlock detected` — deadlock
- `ERROR: canceling statement due to statement timeout` — slow query hit limit
- `ERROR: could not serialize access due to concurrent update` — SERIALIZABLE conflict
- `LOG: checkpoint starting: time` — frequent starts = tuning issue
- `WARNING: database "X" must be vacuumed within N transactions` — wraparound risk

## Gotchas

- `backends` is an OTel counter but behaves gauge-like. Use `max`, not `sum`.
- Missing metric ≠ value zero; usually a receiver scope or permission issue. Say so explicitly.
- Compute cache-hit ratio as ratio-of-sums, not `avg(hit/read)` per instance.
- `rollbacks` includes intentional app-side `ROLLBACK`. Baseline is not zero; the delta vs control is the signal.
