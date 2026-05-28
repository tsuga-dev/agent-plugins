# AWS ElastiCache

Managed Redis or Memcached. Engine-layer = `redis.md`. This file covers AWS-managed-service signals.

## Incident shapes

- **Engine CPU saturation** — `aws_elasticache_engine_cpu_utilization` (not `aws_elasticache_cpu_utilization`) > 90% sustained → command-shape issue
- **Memory pressure / eviction** — `aws_elasticache_database_memory_usage_percentage` near 100%, `aws_elasticache_evictions` climbs
- **Connection saturation** — `aws_elasticache_curr_connections` / `aws_elasticache_curr_connections_memcached` climb, `aws_elasticache_new_connections` spikes, admission fails
- **Replication lag** — `aws_elasticache_replication_lag` (Redis) climbs under primary write burst
- **Traffic management active** — `aws_elasticache_traffic_management_active = 1` → cluster-level throttling engaged

## Key metrics

| Metric | Unit | Signal |
|---|---|---|
| `aws_elasticache_cpu_utilization` | % | Host CPU (includes backups, replication) |
| `aws_elasticache_engine_cpu_utilization` | % | Redis main-thread CPU — THE blocking-command signal |
| `aws_elasticache_freeable_memory` | bytes | Host memory available |
| `aws_elasticache_bytes_used_for_cache` | bytes | Cache footprint |
| `aws_elasticache_database_memory_usage_percentage` | % | Near 100% = eviction imminent |
| `aws_elasticache_cache_hit_rate` | % | Direct cache efficiency |
| `aws_elasticache_cache_hits` / `aws_elasticache_cache_misses` | count | Hit/miss components |
| `aws_elasticache_evictions` | count | Sustained rate = memory pressure |
| `aws_elasticache_curr_connections` | count | Client count |
| `aws_elasticache_new_connections` | count | New-connection rate |
| `aws_elasticache_successful_read_request_latency` / `WriteRequestLatency` | μs | p99 latency |
| `aws_elasticache_replication_lag` | seconds | Primary-replica drift |
| `aws_elasticache_network_bytes_in` / `Out` | bytes/s | Traffic volume |
| `aws_elasticache_error_count` | count | Engine-returned errors |
| `aws_elasticache_authentication_failures` | count | AUTH failures — client misconfig or rotation |

## Derived signals

- `aws_elasticache_database_memory_usage_percentage` — direct memory utilization.
- `aws_elasticache_cache_hit_rate` — cache effectiveness. Cache workloads < 0.95 sustained = concern.
- Per-second derivative of `aws_elasticache_evictions` — sustained + `noeviction` policy = writes failing.
- `maxclients - aws_elasticache_curr_connections` — headroom. `maxclients` is node config, not a metric.

## Log patterns

- `OOM command not allowed when used memory > 'maxmemory'` — memory cap hit
- `MISCONF Redis is configured to save RDB snapshots` — RDB failure; writes blocked
- `Max clients reached` — connection ceiling
- `NOAUTH Authentication required` — client auth misconfig
- `WRONGTYPE Operation against a key holding the wrong kind of value` — app bug
- `LOADING Redis is loading the dataset` — failover / startup state

## Gotchas

- `aws_elasticache_cpu_utilization` vs `aws_elasticache_engine_cpu_utilization` confusion is the #1 misdiagnosis. Always use engine CPU for command-workload analysis.
- `aws_elasticache_replication_lag` only applies to Redis cluster-mode-disabled replicas. Cluster-mode-enabled has partition-level lag harder to surface.
- `aws_elasticache_traffic_management_active = 1` means AWS is throttling the cluster due to overload — secondary signal, not root cause.
- Memory metrics come from `INFO memory`; if engine is blocked by a slow command, scrapes stall and return stale values.
