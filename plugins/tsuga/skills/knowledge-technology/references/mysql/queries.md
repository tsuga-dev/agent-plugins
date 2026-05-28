# MySQL

MySQL / MariaDB relational datastore. Healthy: stable commits, bounded threads, high buffer-pool hit rate, no replication lag, low slow-query count.

## Incident shapes

- **Connection exhaustion** — `connection.count` near `max_connections` → check connection metrics
- **Slow-query storm** — `query.slow.count` spikes, hit rate drops → check handlers + slow log
- **Replication lag** — replica behind primary under write burst → check replication
- **Buffer-pool pressure** — free pages → 0, eviction rises → check buffer-pool metrics
- **Lock contention** — table / row locks serialize writes → check locks

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `mysql.uptime` | seconds | Reset = restart |
| `mysql.threads` (state) | count | `running` climbing = work piling |
| `mysql.connection.count` | count | Denominator of saturation |
| `mysql.connection.errors` | count/s | Any nonzero = rejections |
| `mysql.max_used_connections` | count | Watermark vs `max_connections` |
| `mysql.query.count` | queries/s | Throughput baseline |
| `mysql.query.slow.count` | queries/s | Spike = workload or index regression |
| `mysql.buffer_pool.usage` (kind) | bytes | Free → 0 = eviction pressure |
| `mysql.buffer_pool.operations` | ops/s | Read / read-ahead / miss rates |
| `mysql.row_operations` (operation) | ops/s | Insert / update / delete mix |
| `mysql.locks` | count/s | Row/table lock waits |
| `mysql.handlers` (kind) | ops/s | `read_rnd_next` climbing = full-table scans |
| `mysql.replica.lag_seconds` | seconds | Seconds_Behind_Master |
| `mysql.innodb_data_reads` / `writes` | ops/s | I/O load |

## Derived signals

- `connection.count / max_connections` — utilization. Alert > 0.85.
- `(buffer_pool.reads - buffer_pool.disk_reads) / buffer_pool.reads` — hit ratio. OLTP > 0.99.
- `query.slow.count / query.count` — slow-query rate. Baseline < 0.001.
- `handlers{read_rnd_next} / handlers{read_key}` — full-scan indicator. Rising = missing indexes.

## Log patterns

- `Too many connections` — connection exhaustion
- `Lock wait timeout exceeded; try restarting transaction` — contention
- `Deadlock found when trying to get lock` — deadlock
- `Error 1205 (HY000)` — lock wait timeout (numeric)
- `query_time:` with large value — slow-query entry
- `Aborted connection` — client disconnect mid-query
- `Binlog has been truncated in the middle` — replication corruption

## Gotchas

- `mysql.replica.lag_seconds` is approximate; cross-check `Read_Master_Log_Pos` vs `Exec_Master_Log_Pos` during network blips.
- Aurora MySQL has different metric names; the OTel MySQL receiver does not target Aurora engine endpoints.
- `threads{state=running}` briefly spikes to connection count during lock waits; sustained elevated floor is the real signal.
- Buffer-pool hit ratio < 0.95 is not bad if the workload is intentionally full-scan-heavy (analytics). Know the workload.
