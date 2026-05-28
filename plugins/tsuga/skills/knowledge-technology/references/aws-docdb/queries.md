# AWS DocumentDB

Managed MongoDB-compatible document DB. Healthy: connections under ceiling, cursors bounded, bounded latency, replication lag near zero, cache hit ratio high.

## Incident shapes

- **Connection exhaustion** — `aws_docdb_database_connections` near `aws_docdb_database_connections_limit`
- **Long-running cursors** — `aws_docdb_database_cursors` + `aws_docdb_database_cursors_timed_out` climb → slow scans
- **Storage / IO saturation** — `aws_docdb_read_iops` / `aws_docdb_write_iops` at instance ceiling
- **Replication lag** — primary → replica drift; reads stale
- **Transaction contention** — `aws_docdb_transactions_aborted` climbs under load
- **Cache-miss storm** — `aws_docdb_nvme_storage_cache_hit_ratio` drops → reads fall through to storage

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `aws_docdb_cpu_utilization` | % | Instance CPU |
| `aws_docdb_database_connections` | count | Current connections |
| `aws_docdb_database_connections_limit` | count | Ceiling |
| `aws_docdb_database_cursors` | count | Open cursors; climb = leak |
| `aws_docdb_database_cursors_timed_out` | count | Cursor timeouts |
| `aws_docdb_engine_uptime` | seconds | Reset = restart |
| `aws_docdb_opcounters_query/Command/Insert/Update/Delete` | ops/s | Workload mix |
| `aws_docdb_documents_returned` | docs/s | Read work |
| `aws_docdb_transactions_open` | count | Open multi-doc txns |
| `aws_docdb_transactions_aborted` | count | Abort rate |
| `aws_docdb_read_latency` / `aws_docdb_write_latency` | ms | Per-op latency |
| `aws_docdb_read_iops` / `aws_docdb_write_iops` | ops/s | Storage IO |
| `aws_docdb_nvme_storage_cache_hit_ratio` | ratio | Local NVMe cache hits |
| `StorageNetworkReceive/Transmit Throughput` | bytes/s | Cluster storage network |

## Derived signals

- `aws_docdb_database_connections / aws_docdb_database_connections_limit` — connection utilization. > 0.85 sustained = alert.
- Derivative of `aws_docdb_database_cursors` — leak indicator. Steady positive slope = leak.
- `aws_docdb_transactions_aborted / (aws_docdb_transactions_open + Aborted)` — abort rate. > 0.05 sustained = contention.
- `1 - aws_docdb_nvme_storage_cache_hit_ratio` — cache-miss pressure.

## Log patterns

- `Error Code 50 (MaxTimeMSExpired)` — op exceeded client timeout
- `Error Code 11000 (DuplicateKey)` — unique-index violation
- `WriteConflict` — optimistic-concurrency conflict in txn
- `NetworkTimeout` / `server selection timed out` — client-side connectivity
- `Authentication failed` — IAM / password rotation
- Audit log `type: slowop` — ops above `slowOpThresholdMs`

## Gotchas

- DocumentDB isn't 100% MongoDB-compatible (`$lookup` complex pipelines, change streams differ). Don't assume Mongo guides apply.
- Replicas only serve reads when `readPreference` is explicit. Default-to-primary drivers get no read scaling.
- Multi-doc txn concurrency limits are lower than equivalent MongoDB; `aws_docdb_transactions_aborted` rising is often the cluster limit.
- `aws_docdb_nvme_storage_cache_hit_ratio` is instance-class specific; smaller instances show lower ratios under the same workload.
