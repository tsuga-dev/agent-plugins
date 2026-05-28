# AWS RDS

Managed relational DB (Postgres / MySQL / MariaDB / SQL Server / Oracle / Aurora). Engine-layer behavior = `postgres.md` / `mysql.md`. This file covers RDS-specific signals.

## Incident shapes

- **CPU saturation** — query or vacuum pressure → check `aws_rds_db_load`, `aws_rds_db_load_cpu`, Performance Insights
- **Storage exhaustion** — `aws_rds_free_storage_space → 0` blocks writes, `aws_rds_write_iops` collapses
- **IOPS / burst credit depletion** — gp2 `aws_rds_burst_balance` crash OR gp3 `aws_rds_ebsio_balance` / `aws_rds_ebs_byte_balance` → IOPS cliff
- **Replication lag** — `aws_rds_rds_to_aurora_postgre_sql_replica_lag` climbs under primary write burst
- **Connection ceiling** — `aws_rds_database_connections` near engine `max_connections` (usually app-side)
- **Transaction-log bloat** — `aws_rds_transaction_logs_disk_usage` grows when replication slots orphan

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `aws_rds_cpu_utilization` | % | Host CPU; decompose via aws_rds_db_load_cpu vs aws_rds_db_load_non_cpu |
| `aws_rds_database_connections` | count | Compare to engine `max_connections` |
| `aws_rds_free_storage_space` | bytes | Zero = writes blocked. Missing? infer from aws_rds_write_iops collapse |
| `aws_rds_read_iops` / `aws_rds_write_iops` | ops/s | Workload intensity |
| `aws_rds_read_latency` / `aws_rds_write_latency` | seconds | Per-op latency |
| `aws_rds_burst_balance` | % | gp2 only; zero = IOPS throttled to baseline |
| `aws_rds_ebs_byte_balance` / `aws_rds_ebsio_balance` | % | gp3/Aurora credit pools |
| `aws_rds_db_load` / `aws_rds_db_load_cpu` / `aws_rds_db_load_non_cpu` | avg sessions | Active sessions; CPU vs wait decomposition |
| `aws_rds_rds_to_aurora_postgre_sql_replica_lag` | seconds | Read-replica staleness |
| `aws_rds_transaction_logs_disk_usage` | bytes | Grows when replication slot stuck |
| `aws_rds_oldest_replication_slot_lag` | bytes | Which slot is the bottleneck |
| `aws_rds_deadlocks` | count | Engine-layer conflicts |
| `aws_rds_freeable_memory` | bytes | Cache-pressure signal |

## Derived signals

- `(aws_rds_read_iops + aws_rds_write_iops) / provisioned_IOPS` — IOPS saturation. > 0.9 sustained = throttling.
- `aws_rds_db_load_cpu / aws_rds_db_load` — high → CPU-bound queries; low with high aws_rds_db_load → locks/I/O waits.
- Write throttle pattern: aws_rds_write_iops collapse + aws_rds_write_latency spike + low `aws_rds_free_storage_space` OR low balance.

## Log patterns

RDS events:

- `DB instance storage auto-scaled` — autoscaling fired; often precedes "healthy" verdict
- `The database instance ran out of storage space` — hard failure
- `DB instance restarted` — engine restart, not user-initiated
- `Read Replica has fallen behind` — replication lag alert
- `Multi-AZ failover started` / `completed` — failover event
- `Logical replication slot was dropped` — explains sudden `aws_rds_transaction_logs_disk_usage` drop

## Gotchas

- `aws_rds_free_storage_space` drops below threshold even with autoscaling enabled; auto-recovery ends the investigation.
- RDS event messages lag real events up to 1-2 min. Don't pin 1-min-precision timelines on event timestamps.
- `aws_rds_burst_balance` applies to gp2 only. Flat 100% on gp3 means "not applicable," not "healthy."
- `aws_rds_rds_to_aurora_postgre_sql_replica_lag` can be stale if receiver scrape stalls. Cross-check with logical-slot lag via log.
- High `aws_rds_db_load` with low CPU usually = io_wait or lock wait. Use Performance Insights' top-waits breakdown.
