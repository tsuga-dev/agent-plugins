# AWS EFS

Shared NFS filesystem. Mounted by EC2 / ECS / EKS / Lambda. Healthy: throughput within limits, metadata / data IO balanced, burst credits positive, connection count reasonable.

## Incident shapes

- **Burst credit exhaustion** — `aws_efs_burst_credit_balance → 0` → IOPS throttled to baseline → latency cliff
- **IO limit hit** — `aws_efs_percent_io_limit = 100%` sustained (General Purpose mode) → consider Max I/O or provisioned throughput
- **Throughput ceiling** — metered throughput at `aws_efs_permitted_throughput` → reads/writes slow
- **Connection storm** — `aws_efs_client_connections` spikes (often Lambda cold-start storms)
- **Metadata-heavy workload** — `aws_efs_metadata_io_bytes` dominates → small-file or listdir pattern

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `aws_efs_percent_io_limit` | % | GP-mode saturation (N/A in Max I/O mode) |
| `aws_efs_burst_credit_balance` | bytes | 0 = throttled to baseline |
| `aws_efs_permitted_throughput` | bytes/s | Current allowed throughput |
| `aws_efs_metered_io_bytes` | bytes | Total IO this interval |
| `aws_efs_total_io_bytes` | bytes | Incl. metadata ops |
| `By` / `MISSING` | bytes | User-data IO |
| `aws_efs_metadata_io_bytes` | bytes | Metadata ops (list, stat, mkdir) |
| `aws_efs_client_connections` | count | Open mounts |
| `aws_efs_storage_bytes` | bytes | Filesystem size (by class) |
| `MISSING` | seconds | Cross-region replication lag |

## Derived signals

- `aws_efs_permitted_throughput - aws_efs_metered_io_bytes` — throughput headroom. Zero = bound.
- `aws_efs_metadata_io_bytes / aws_efs_total_io_bytes` — metadata dominance. > 0.3 = small-files-heavy workload.
- `aws_efs_burst_credit_balance / aws_efs_metered_io_bytes` — seconds of runway at current rate; predict the cliff.

## Log patterns

EFS has no direct logs. Use NFS-mount + app + kernel logs:

- `NFS server not responding` / `still trying` — mount hiccup
- `server X.X.X.X OK` — recovered
- `stale NFS file handle` — mount reset after failure
- `rpc.statd` issues — lock daemon
- `Permission denied` — IAM / POSIX

## Gotchas

- Burst throughput is based on filesystem size; a 1 GB filesystem has minimal baseline. Need provisioned throughput or a bigger dataset.
- `aws_efs_permitted_throughput` drop is often the visible part of burst-credit exhaustion, not a separate incident.
- Lambda + EFS spawns many short-lived connections; `aws_efs_client_connections` spikes during cold-start storms are usually benign.
- Metadata-heavy ops (`ls -R` on many files) exhaust burst credits fast even when total bytes are small.
- Cross-AZ NFS latency is 2-3 ms minimum; different-AZ consumers always see higher latency than same-AZ.
